{
  config,
  pkgs,
  lib,
  ...
}:
let
  # One key on, same key off — the record-gif-toggle pattern, for the
  # wshowkeys keystroke overlay (bind to e.g. Ctrl+6 in COSMIC's custom
  # shortcuts, beside the screenshot and GIF keys). No FIFO/listener
  # indirection like the capture triggers need: wshowkeys never grabs the
  # seat interactively, so launching it straight from a keybind works.
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
        /run/wrappers/bin/wshowkeys \
            -F "''${WSHOWKEYS_FONT:-Libertinus Keyboard 32}" \
            -a bottom -m 80 -t 2 &
        echo "$!" > "$PIDFILE"
        ${pkgs.libnotify}/bin/notify-send "Key display" "On — keystrokes shown on screen"
    fi
  '';
in
{
  # Add system wide packages
  environment.systemPackages = [
    wshowkeys-toggle
    (pkgs.wrapOBS {
      plugins = with pkgs.obs-studio-plugins; [
        wlrobs # wayland capture support
        obs-move-transition # Plugin for OBS Studio to move source to a new position during scene transition
        obs-backgroundremoval # OBS plugin to replace the background in portrait images and video
        obs-3d-effect # create 3d effects for transitions
        waveform # show waveform of audio
        #obs-cli # control obs from cli
        droidcam-obs # use droidcam app on your phone to let it work as a camera. Also can remote control OBS
        obs-pipewire-audio-capture
        input-overlay # show your keyboard and mouse on screen
        obs-text-pthread # advanced tweaks for displaying text - see https://github.com/norihiro/obs-text-pthread
        obs-shaderfilter # crazy effects - see https://github.com/exeldro/obs-shaderfilter
        obs-source-record # record a source independently of the whole scene
        obs-vintage-filter # make a source look old fashioned
        #obs-vertical-canvas # use with source record to record tiktok style vertical video at the same time as your normal recording
      ];
    })
  ];
  # On-screen keystroke display for screencasts and demos — pairs with the
  # recordings OBS (above) and record-gif make. The NixOS module rather than
  # a plain package: wshowkeys reads /dev/input directly, and the module
  # provides the setuid wrapper that makes that work for a normal user.
  programs.wshowkeys.enable = true;

  # SIL OFL. Libertinus Keyboard renders each character inside a keycap
  # outline — the default face wshowkeys-toggle asks for.
  fonts.packages = [ pkgs.libertinus ];

  boot.extraModulePackages = with config.boot.kernelPackages; [
    v4l2loopback
  ];
  boot.extraModprobeConfig = ''
    options v4l2loopback devices=1 video_nr=1 card_label="OBS Cam" exclusive_caps=1
  '';
  security.polkit.enable = true;
}
