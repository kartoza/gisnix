# Pre-seeds OBS so `gisnix obs-setup <kartoza|qgis>` (utils/obs-setup.py)
# has something to talk to, and so the host's existing bootTheme choice
# (kartoza/qgis — see software/services/system/boot-themes/) decides which
# brand's scene collection OBS opens into, the same way it already decides
# Plymouth/GRUB branding. This module does NOT build the scenes themselves
# — obs-websocket has no "import this JSON" request, so scenes only exist
# once a human (or `obs-setup`) creates them through OBS itself. See
# docs/user/keyboard.md for the caps+space cycle that switches between them
# once they do.
#
# Also forces recording quality to OBS's own "Lossless" preset on every
# existing profile — confirmed against obs-studio's own
# frontend/utility/SimpleOutput.cpp: RecQuality=Lossless hardcodes the
# ffmpeg_output path to utvideo (lossless intra) video + pcm_s16le audio in
# an AVI container, ignoring RecEncoder/RecFormat2 entirely. That is
# genuinely the highest quality OBS can record at, at the cost of being
# the opposite of small: an hour of 1080p60 easily reaches tens of GB. Drop
# RecQuality to "HQ" (CRF ~16 x264, ordinary mp4/mkv, a fraction of the
# size, still visually close to lossless) if disk space becomes the
# limiting factor.
{
  config,
  lib,
  pkgs,
  hostConfig,
  ...
}:
let
  # Cross-referenced with kanata-keyboard.nix's identical obsScenePrefix —
  # if you change one, change the other, or a host's keyboard starts
  # switching to scenes that don't exist in its own OBS.
  brand = if (hostConfig.bootTheme or "kartoza") == "qgis" then "QGIS" else "Kartoza";

  # Per-user "who is this" for obs-setup.py's lower-third/card text —
  # name from the same NixOS account field `id -c`/`finger` would show,
  # email from kartoza.userEmails (declared per-user, e.g. users/tim.nix:
  # `kartoza.userEmails.tim = "tim@kartoza.com";` — the exact same source
  # kanata-email.nix already reads for its own press-time email macro).
  # Nothing here is asked interactively; obs-setup.py's own gum fallback
  # covers whichever of these a user hasn't declared (most often: role,
  # which has no NixOS field to read at all).
  identityFiles = lib.mapAttrs' (
    username: userCfg:
    lib.nameValuePair "xdg/obs-scenes/identity-${username}.json" {
      mode = "0444";
      text = builtins.toJSON {
        name = if userCfg.description or "" != "" then userCfg.description else null;
        email = config.kartoza.userEmails.${username} or null;
      };
    }
  ) (lib.filterAttrs (_: userCfg: userCfg.isNormalUser or false) config.users.users);

  # OBS's global.ini carries a LOT the user edits through OBS itself (window
  # geometry, recent files, …) — unlike herdr/kitty's config files, this is
  # not something gisnix can own wholesale with a symlink. Instead: once
  # that bootTheme's collection actually exists, point OBS at it — without
  # touching anything else a human already set.
  #
  # The websocket server's own settings do NOT live in global.ini, despite
  # that being the obvious guess (and what an earlier version of this file
  # wrote, silently doing nothing on any host that had ever launched OBS
  # before). Checked against obs-websocket's own source
  # (src/Config.cpp/Config::Load): it reads a plugin-private JSON file at
  # obs_module_config_path("obs-websocket")/config.json — on Linux that is
  # ~/.config/obs-studio/plugin_config/obs-websocket/config.json — with ITS
  # OWN key names (server_enabled/server_port/auth_required/first_load),
  # not the ServerEnabled/ServerPort/AuthRequired names global.ini's
  # [OBSWebSocket] section would use. global.ini only matters on the very
  # first-ever OBS launch, as a one-time migration source
  # (MigrateGlobalConfigData) — useless on a host where OBS already has a
  # config.json, which describes every real host by the time this was
  # found. Loopback-only use (obs-cli/obs-setup both run on this same
  # machine), so no auth and no firewall rule.
  #
  # The python body MUST sit flush at column 0 — a bash heredoc with a
  # quoted delimiter ('PYEOF') takes its content completely literally, so
  # any indentation added here to match the surrounding nix/bash would
  # become a Python IndentationError on the heredoc's first line.
  seedObsConfig = pkgs.writeShellApplication {
    name = "gisnix-obs-seed-config";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      for dir in /home/*; do
        user="$(basename "$dir")"
        id "$user" &>/dev/null || continue
        [ -d "$dir" ] || continue

        mkdir -p "$dir/.config/obs-studio"
        python3 - "$dir/.config/obs-studio/global.ini" "${brand}" <<'PYEOF'
import configparser, glob, json, os, sys

path, brand = sys.argv[1], sys.argv[2]
obs_studio_dir = os.path.dirname(path)

# The websocket server's actual config — see this file's own comment for
# why this is a plugin-private JSON file, not global.ini's [OBSWebSocket].
ws_config_path = os.path.join(obs_studio_dir, "plugin_config", "obs-websocket", "config.json")
os.makedirs(os.path.dirname(ws_config_path), exist_ok=True)
ws_config = {}
if os.path.exists(ws_config_path):
    with open(ws_config_path) as f:
        try:
            ws_config = json.load(f)
        except json.JSONDecodeError:
            ws_config = {}
ws_config["server_enabled"] = True
ws_config["server_port"] = 4455
ws_config["auth_required"] = False
# Only set if absent (a genuinely fresh config.json) — OBS's own
# Config::Load() auto-generates a server_password on first_load=true if
# none is set yet, which is pointless work for a no-auth loopback setup.
# An existing config.json's own first_load value (already false, past
# that point) is left alone either way.
ws_config.setdefault("first_load", False)
with open(ws_config_path, "w") as f:
    json.dump(ws_config, f, indent=4)

# strict=False: a real OBS-written global.ini can carry a duplicate key in
# one section (seen live: two "MaxLogs" under [General]) — Python's
# ConfigParser is stricter about that than OBS's own ini reader and
# refuses to even load the file. strict=False keeps the last value, same
# as OBS does, and the rewrite below collapses the duplicate for good.
cfg = configparser.ConfigParser(strict=False)
cfg.optionxform = str
if os.path.exists(path):
    cfg.read(path)

scenes_file = os.path.join(os.path.dirname(path), "basic", "scenes", brand + ".json")
if os.path.exists(scenes_file):
    cfg.setdefault("Basic", {})
    cfg["Basic"]["SceneCollection"] = brand
    cfg["Basic"]["SceneCollectionFile"] = brand

with open(path, "w") as f:
    cfg.write(f)

# Recording quality — every profile that exists yet. None exist before
# OBS's first launch (profiles, unlike global.ini, are never created by
# this activation script), so this is a no-op until then; the next
# rebuild after that first launch picks the new profile up.
for basic_ini in glob.glob(os.path.join(obs_studio_dir, "basic", "profiles", "*", "basic.ini")):
    pcfg = configparser.ConfigParser(strict=False)
    pcfg.optionxform = str
    pcfg.read(basic_ini)

    pcfg.setdefault("SimpleOutput", {})
    pcfg["SimpleOutput"]["RecQuality"] = "Lossless"
    pcfg["SimpleOutput"].setdefault("RecEncoder", "x264")
    pcfg["SimpleOutput"].setdefault("RecFormat2", "mkv")
    pcfg["SimpleOutput"].setdefault("RecAudioEncoder", "aac")
    pcfg["SimpleOutput"].setdefault("RecTracks", "1")
    if not pcfg["SimpleOutput"].get("FilePath"):
        home_dir = os.path.dirname(os.path.dirname(obs_studio_dir))  # strip /.config/obs-studio
        pcfg["SimpleOutput"]["FilePath"] = os.path.join(home_dir, "Videos")

    with open(basic_ini, "w") as f:
        pcfg.write(f)
PYEOF

        chown -hR "$user":"$(id -gn "$user")" "$dir/.config/obs-studio" 2>/dev/null || true
      done
    '';
  };
in
{
  # Lato — the brand pack's own typeface — so text_ft2_source_v2's
  # "Lato"/"Lato Bold"/"Lato Black" face names resolve via fontconfig.
  # Open-source (OFL), packaged in nixpkgs proper; no private asset needed
  # for the typography, unlike the motif artwork this deliberately avoids
  # (see obs-setup.py's own BRANDS comment for why).
  fonts.packages = [ pkgs.lato ];

  environment.etc = identityFiles // {
    # obs-setup.py's default KARTOZA_LOGO path — QGIS has no vendored logo
    # (see obs-setup.py's own BRANDS comment), so only Kartoza needs an
    # asset shipped here.
    "xdg/obs-scenes/kartoza-logo.png" = {
      mode = "0444";
      source = ../../../resources/kartoza-logo.png;
    };
  };

  system.activationScripts.gisnixObsSeedConfig = ''
    ${seedObsConfig}/bin/gisnix-obs-seed-config
  '';
}
