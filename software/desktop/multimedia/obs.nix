{
  config,
  pkgs,
  lib,
  ...
}:
let
  # Our own wl-find-cursor build. nixpkgs-unstable carries one, but its
  # derivation fails on a real rebuild: wayland-scanner dies with "Could
  # not open input file" on a protocols path that demonstrably exists —
  # some __structuredAttrs interaction in that packaging (its make flags
  # arrive escaped too, `PREFIX=\$\(out\)` in the log). Same upstream
  # source pin, built plainly against the STABLE wayland stack instead;
  # one C file, nothing exotic.
  wl-find-cursor = pkgs.stdenv.mkDerivation {
    pname = "wl-find-cursor";
    version = "0-unstable-2026-02-03";

    src = pkgs.fetchFromGitHub {
      owner = "cjacker";
      repo = "wl-find-cursor";
      rev = "ce1a125702b466dc537c5490f7888b4a68dee883";
      hash = "sha256-IUreWEOWF1loS5SiAh8XPFrKE35Pxv6e8hhvdtNvjiU=";
    };

    nativeBuildInputs = [ pkgs.wayland-scanner ];
    buildInputs = [ pkgs.wayland ];

    postPatch = ''
      substituteInPlace Makefile \
        --replace-fail "/usr/share/wayland-protocols" "${pkgs.wayland-protocols}/share/wayland-protocols" \
        --replace-fail "gcc" "cc" \
        --replace-fail "install: default" "install: all"
    '';

    makeFlags = [ "PREFIX=$(out)" ];

    meta = {
      description = "Highlight and print the mouse cursor position on Wayland";
      homepage = "https://github.com/cjacker/wl-find-cursor";
      license = lib.licenses.mit;
      mainProgram = "wl-find-cursor";
    };
  };

  # Press-to-flash cursor locator — wl-find-cursor draws a growing circle
  # at the pointer and EXITS on its own (or the moment the mouse moves),
  # so unlike wshowkeys-toggle below there is nothing to stop; the pidfile
  # only guards against stacking a second animation on a double-press.
  # Bind to e.g. Ctrl+7, continuing the capture row. circle in Kartoza yellow (brand.nix highlight1),
  # 0xAARRGGBB.
  find-cursor = pkgs.writeShellScriptBin "find-cursor" ''
    set -uo pipefail

    PIDFILE="''${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR not set}/kartoza-find-cursor.pid"

    if [[ -f "$PIDFILE" ]] && ${pkgs.procps}/bin/ps -p "$(cat "$PIDFILE")" >/dev/null 2>&1; then
        exit 0
    fi

    # -e true: a NO-OP "mouse emulation" command. wl-find-cursor refuses
    # to start on compositors without zwlr_virtual_pointer_v1 (cosmic-comp
    # is one) unless -e provides a motion-emulating command — but it only
    # needs that motion to coax a pointer.enter out of the compositor, and
    # cosmic-comp sends enter the moment the overlay maps (confirmed on a
    # real session: coordinates arrive with zero mouse movement). So the
    # protocol gap costs nothing here and the emulation can be a no-op.
    ${wl-find-cursor}/bin/wl-find-cursor -e true -d 1200 -s 400 -c 0xcfdf9e2f &
    echo "$!" > "$PIDFILE"
    wait || true
    rm -f "$PIDFILE"
  '';

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
  # Add system wide packages
  environment.systemPackages = [
    find-cursor
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
