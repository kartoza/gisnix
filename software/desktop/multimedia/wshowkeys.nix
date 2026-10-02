# wshowkeys — on-screen keystroke display for screencasts and demos,
# pairing with OBS and record-gif. A toggle in the capture row: bind to
# Ctrl+6 beside the screenshot/GIF/find-cursor keys.
{ pkgs, ... }:
let
  # One key on, same key off — the record-gif-toggle pattern. No
  # FIFO/listener indirection like the capture triggers need: wshowkeys
  # never grabs the seat interactively, so launching it straight from a
  # keybind works.
  #
  # /run/wrappers/bin, not the store path: wshowkeys reads /dev/input and
  # only the setuid wrapper programs.wshowkeys installs (below) may do
  # that as a normal user.
  wshowkeys-toggle = pkgs.writeShellScriptBin "wshowkeys-toggle" ''
    set -uo pipefail

    PIDFILE="''${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR not set}/kartoza-wshowkeys.pid"

    if [[ -f "$PIDFILE" ]] && ${pkgs.procps}/bin/ps -p "$(cat "$PIDFILE")" >/dev/null 2>&1; then
        kill "$(cat "$PIDFILE")"
        rm -f "$PIDFILE"
        ${pkgs.libnotify}/bin/notify-send "Key display" "Off"
    else
        # Libertinus Keyboard (fonts.packages below) draws every character
        # inside a keycap outline. Override with WSHOWKEYS_FONT, a Pango
        # spec like 'monospace 28'.
        #
        # This is the DreamMaoMao fork (see overlays/default.nix): -t is in
        # MILLISECONDS there, and the display width is capped (oldest keys
        # drop off) so continuous typing cannot overflow the screen — the
        # original only ever cleared after a typing pause.
        /run/wrappers/bin/wshowkeys \
            -F "''${WSHOWKEYS_FONT:-Libertinus Keyboard 32}" \
            -a bottom -m 80 -t 2000 &
        echo "$!" > "$PIDFILE"
        ${pkgs.libnotify}/bin/notify-send "Key display" "On — keystrokes shown on screen"
    fi
  '';
in
{
  environment.systemPackages = [ wshowkeys-toggle ];

  # The NixOS module rather than a plain package: wshowkeys reads
  # /dev/input directly, and the module provides the setuid wrapper that
  # makes that work for a normal user.
  programs.wshowkeys.enable = true;

  # SIL OFL. Libertinus Keyboard renders each character inside a keycap
  # outline — the default face wshowkeys-toggle asks for.
  fonts.packages = [ pkgs.libertinus ];
}
