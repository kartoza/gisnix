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
  pkgs,
  hostConfig,
  ...
}:
let
  brand = if (hostConfig.bootTheme or "kartoza") == "qgis" then "QGIS" else "Kartoza";

  # OBS's global.ini carries a LOT the user edits through OBS itself (window
  # geometry, recent files, …) — unlike herdr/kitty's config files, this is
  # not something gisnix can own wholesale with a symlink. Instead: ensure
  # the [OBSWebSocket] section is on (obs-setup and the kanata obs layer
  # both need it) and, once that bootTheme's collection actually exists,
  # that OBS opens into it — without touching anything else a human already
  # set. Loopback-only use (obs-cli/obs-setup both run on this same
  # machine), so no auth and no firewall rule.
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
import configparser, glob, os, sys

path, brand = sys.argv[1], sys.argv[2]
cfg = configparser.ConfigParser()
cfg.optionxform = str
if os.path.exists(path):
    cfg.read(path)

cfg.setdefault("OBSWebSocket", {})
cfg["OBSWebSocket"]["ServerEnabled"] = "true"
cfg["OBSWebSocket"]["ServerPort"] = "4455"
cfg["OBSWebSocket"]["AuthRequired"] = "false"

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
obs_studio_dir = os.path.dirname(path)
for basic_ini in glob.glob(os.path.join(obs_studio_dir, "basic", "profiles", "*", "basic.ini")):
    pcfg = configparser.ConfigParser()
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
  # obs-setup.py's default KARTOZA_LOGO path — QGIS has no vendored logo
  # (see obs-setup.py's own BRANDS comment), so only Kartoza needs an asset
  # shipped here.
  environment.etc."xdg/obs-scenes/kartoza-logo.png" = {
    mode = "0444";
    source = ../../../resources/kartoza-logo.png;
  };

  system.activationScripts.gisnixObsSeedConfig = ''
    ${seedObsConfig}/bin/gisnix-obs-seed-config
  '';
}
