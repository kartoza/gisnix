# Pre-seeds OBS so `gisnix obs-setup <kartoza|qgis>` (utils/obs-setup.py)
# has something to talk to, and so the host's existing bootTheme choice
# (kartoza/qgis — see software/services/system/boot-themes/) decides which
# brand's scene collection OBS opens into, the same way it already decides
# Plymouth/GRUB branding. This module does NOT build the scenes themselves
# — obs-websocket has no "import this JSON" request, so scenes only exist
# once a human (or `obs-setup`) creates them through OBS itself. See
# docs/user/keyboard.md for the caps+space cycle that switches between them
# once they do.
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
import configparser, os, sys

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
PYEOF

        chown -h "$user":"$(id -gn "$user")" "$dir/.config/obs-studio/global.ini" 2>/dev/null || true
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
