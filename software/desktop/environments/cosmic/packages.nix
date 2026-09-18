# COSMIC Desktop Packages
# Applications and utilities for the COSMIC desktop environment
# COSMIC packages come from nixpkgs-unstable via overlay in overlays/default.nix
{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  hostConfig,
  ...
}:

with lib;

let
  cfg = config.kartoza.cosmic;
  # COSMIC packages come from nixpkgs-unstable via overlay
  cosmicPkgs = pkgs;
  # Override the COSMIC App Library panel button icon with the Kartoza
  # logo. The panel button resolves its icon from the icon theme by
  # app-id (com.system76.CosmicAppLibrary), so we just ship our SVG at
  # the same hicolor path and let lib.hiPrio (applied at the use site
  # below) win the path conflict against cosmic-applets.
  kartoza-cosmic-app-library-icon = pkgs.runCommand "kartoza-cosmic-app-library-icon" { } ''
    mkdir -p $out/share/icons/hicolor/scalable/apps
    cp ${../../../../resources/kartoza-logo.svg} \
       $out/share/icons/hicolor/scalable/apps/com.system76.CosmicAppLibrary.svg
  '';

  # Screenshot script that opens Satty for annotation
  screenshot-satty = pkgs.writeShellScriptBin "screenshot-satty" ''
    set -euo pipefail

    SCREENSHOT_DIR="''${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
    mkdir -p "$SCREENSHOT_DIR"

    TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
    TEMP_FILE="/tmp/screenshot-$TIMESTAMP.png"

    MODE="''${1:-region}"

    case "$MODE" in
        region)
            REGION=$(${pkgs.slurp}/bin/slurp) || exit 0
            ${pkgs.grim}/bin/grim -g "$REGION" "$TEMP_FILE"
            ;;
        screen)
            ${pkgs.grim}/bin/grim "$TEMP_FILE"
            ;;
        *)
            echo "Usage: $0 [region|screen]"
            exit 1
            ;;
    esac

    if [[ -f "$TEMP_FILE" ]]; then
        ${pkgs.satty}/bin/satty --filename "$TEMP_FILE" --output-filename "$SCREENSHOT_DIR/screenshot-$TIMESTAMP.png"
        rm -f "$TEMP_FILE"
    else
        ${pkgs.libnotify}/bin/notify-send "Screenshot" "Failed to capture screenshot"
        exit 1
    fi
  '';

  # Region-to-GIF recorder. Mirrors screenshot-satty: slurp defines the area,
  # then the capture tool runs against that geometry.
  #
  # WHY NOT wlgif/wf-recorder. wlgif drives wf-recorder, which speaks only
  # zwlr_screencopy_unstable_v1. cosmic-comp does NOT implement that protocol,
  # so every capture died with
  #
  #   compositor doesn't support wlr-screencopy-unstable-v1
  #
  # surfaced by wlgif as the useless "wf-recorder exited: exit status: 1", for
  # full-screen and region alike. An older comment here claimed cosmic-comp
  # implements wlr-screencopy "because grim works" — that was wrong. grim 1.5
  # speaks BOTH the wlr protocol and ext-image-copy-capture-v1, and under COSMIC
  # it succeeds via the latter. wlgif's other backend (portal) does work, but it
  # raises the portal's own output/window picker and ignores the slurp region,
  # which defeats the point of selecting one.
  #
  # wl-screenrec speaks ext-image-copy-capture-v1 as well, takes --geometry in
  # exactly slurp's "x,y WxH" form, and needs no picker. It writes video, so a
  # two-pass palettegen/paletteuse converts to GIF; a naive one-pass conversion
  # quantises to a fixed 256-colour palette and bands badly on UI gradients.
  record-gif = pkgs.writeShellScriptBin "record-gif" ''
    set -euo pipefail

    # Lets Ctrl+C, run directly in a terminal, behave exactly like
    # record-gif-stop instead of aborting silently with nothing saved.
    #
    # Without this: SIGINT from a terminal goes to the whole foreground
    # process group, which includes wl-screenrec AND this script itself
    # (backgrounding with `&` does not put a child in a new group here —
    # there is no `set -m`). wl-screenrec finalises correctly, but bash's
    # OWN default disposition for an uncaught SIGINT is to terminate —
    # during the `wait` below, not after it — so the ffmpeg conversion
    # and the notify-send that reports where the GIF landed never run.
    # `wait ... || true` only swallows wait's exit STATUS; it does
    # nothing to stop the signal from killing the shell that called it.
    #
    # An EMPTY trap (trap on an empty command, no argument text at all)
    # looks like the fix but silently breaks the *working* stop path
    # instead: an empty trap is a real SIG_IGN, and SIG_IGN is the one
    # disposition POSIX has exec() PRESERVE across a fork+exec — so
    # wl-screenrec, forked after this trap is set, would inherit it and
    # start ignoring SIGINT too, which is exactly what record-gif-stop
    # sends it. A trap with an actual command is different: it is a
    # CAUGHT signal, and POSIX has exec() RESET any caught signal to
    # default in the new program image — so wl-screenrec's own SIGINT
    # handling is unaffected either way, and only this shell's premature
    # exit is fixed.
    trap 'true' INT

    RECORDING_DIR="''${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings"
    mkdir -p "$RECORDING_DIR"

    TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
    OUTPUT="$RECORDING_DIR/recording-$TIMESTAMP.gif"

    # 0 = record until record-gif-stop is invoked. A numeric argument caps it.
    DURATION="''${1:-0}"

    PIDFILE="''${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR not set}/kartoza-record-gif.pid"

    if [[ -f "$PIDFILE" ]] && ${pkgs.procps}/bin/ps -p "$(cat "$PIDFILE")" >/dev/null 2>&1; then
        ${pkgs.libnotify}/bin/notify-send "Record GIF" \
          "A recording is already running — stop it first."
        exit 1
    fi

    WORKDIR=$(mktemp -d)
    # Cleans up the PIDFILE too, not just WORKDIR — belt-and-braces for the
    # early-exit paths below (slurp cancelled, selection too small), which
    # `exit` before the explicit `rm -f "$PIDFILE"` near the bottom of this
    # script is ever reached. EXIT fires on every one of those the same way
    # it fires on a normal finish, so nothing is left stale regardless of
    # which door this script leaves by.
    trap 'rm -rf "$WORKDIR"; rm -f "$PIDFILE"' EXIT
    RAW="$WORKDIR/raw.mp4"

    # Claims the PIDFILE with THIS SCRIPT's own PID before slurp ever runs
    # — not wl-screenrec's PID yet, that does not exist until slurp
    # returns a completed selection, which is exactly the bug this line
    # fixes. Interactive selection can take an arbitrary, possibly long
    # time, and for all of it the PIDFILE used to not exist at all — so
    # record-gif-toggle, pressed anywhere in that window, saw "nothing is
    # recording" and started a SECOND slurp session instead of stopping
    # the first. Overwritten below with wl-screenrec's real PID once
    # launched, at which point record-gif-stop's SIGINT reaches it exactly
    # as before. Pressed while still on this placeholder, SIGINT instead
    # reaches this shell, which `trap 'true' INT` above already catches
    # and ignores — a harmless no-op, not a cancel, since that trap does
    # not propagate into the still-blocking slurp call either; the pending
    # selection has to be finished or Escaped by hand. Silently starting a
    # redundant second recording was the worse failure of the two.
    echo "$$" > "$PIDFILE"

    # slurp fails (exit 1) when the selection is cancelled with Escape; that is
    # a normal user action, not an error, so exit quietly.
    #
    # Captured via command substitution, THEN split with a here-string —
    # not `read ... < <(slurp -f "...")` directly. slurp's -f output has
    # no trailing newline (its DEFAULT format does; a custom -f format
    # only gets one if you put "\n" in it, and this one does not). Fed
    # straight into `read` via process substitution, that missing
    # newline means `read` hits EOF before seeing one — which makes
    # `read` return non-zero EVEN THOUGH it parsed all four fields
    # correctly, indistinguishable here from slurp's own real Escape-
    # cancel failure, so a completed selection silently hit the exact
    # same `|| exit 0` a cancellation does (confirmed empirically: `read
    # -r A B C D < <(printf "1 2 3 4")`, no trailing newline, exits 1
    # with $A/$B/$C/$D all populated correctly anyway). `<<<` always
    # newline-terminates whatever it is fed, so the second read cannot
    # hit this; SLURP_OUT's own assignment still carries slurp's real
    # exit status for `|| exit 0` to catch an actual cancellation on.
    # Same shape screenshot-satty already uses successfully for exactly
    # this reason (command substitution, not process substitution).
    #
    # Read the fields separately rather than pre-formatted, because the size
    # needs fixing up before it is handed on (see below).
    SLURP_OUT=$(${pkgs.slurp}/bin/slurp -f "%x %y %w %h") || exit 0
    read -r SEL_X SEL_Y SEL_W SEL_H <<< "$SLURP_OUT"

    # h264 with yuv420p chroma subsampling requires EVEN width and height, and
    # the geometry is passed to the encoder as-is. Round both dimensions down to
    # the nearest even number; losing at most one pixel per axis is
    # imperceptible and makes any selection recordable.
    SEL_W=$(( SEL_W - SEL_W % 2 ))
    SEL_H=$(( SEL_H - SEL_H % 2 ))

    # A degenerate selection (a click rather than a drag) rounds to zero and
    # would fail deeper in with a worse message.
    if (( SEL_W < 2 || SEL_H < 2 )); then
        ${pkgs.libnotify}/bin/notify-send "Record GIF" \
          "Selection too small to record."
        exit 1
    fi

    # wl-screenrec's --geometry is slurp's native "x,y WxH".
    GEOMETRY="''${SEL_X},''${SEL_Y} ''${SEL_W}x''${SEL_H}"

    ${pkgs.libnotify}/bin/notify-send "Record GIF" \
      "Recording ''${SEL_W}x''${SEL_H} — stop with the record-gif-stop keybind."

    # --low-power=off: this GPU has no usable low-power H264 entrypoint
    # ("No usable encoding entrypoint found for profile VAProfileH264High"),
    # so wl-screenrec warns, falls back to the normal VAAPI encoder and works.
    # Asking for the working mode up front keeps that noise out of the journal.
    #
    # wl-screenrec has no duration flag; a capped run is a SIGINT from timeout,
    # which is the same clean-stop path record-gif-stop uses.
    if (( DURATION > 0 )); then
        ${pkgs.coreutils}/bin/timeout -s INT "$DURATION" \
          ${pkgs.wl-screenrec}/bin/wl-screenrec --low-power=off \
            --geometry "$GEOMETRY" -f "$RAW" &
    else
        ${pkgs.wl-screenrec}/bin/wl-screenrec --low-power=off \
          --geometry "$GEOMETRY" -f "$RAW" &
    fi
    REC_PID=$!
    echo "$REC_PID" > "$PIDFILE"

    # SIGINT is wl-screenrec's finalise-and-exit path, but `timeout -s INT` still
    # reports 124 and a bare SIGINT shows as 130. Both mean "stopped normally",
    # so judge success on whether a playable file landed rather than on status.
    wait "$REC_PID" || true
    rm -f "$PIDFILE"

    if [[ ! -s "$RAW" ]]; then
        ${pkgs.libnotify}/bin/notify-send "Record GIF" "Recording failed — nothing captured"
        exit 1
    fi

    ${pkgs.libnotify}/bin/notify-send "Record GIF" "Converting to GIF…"

    # Pass 1 builds a palette from the frames actually present (stats_mode=diff
    # weights the moving parts, which is what a screen recording is about);
    # pass 2 maps the video onto it.
    ${pkgs.ffmpeg}/bin/ffmpeg -y -v error -i "$RAW" \
        -vf "fps=15,scale=iw:-1:flags=lanczos,palettegen=stats_mode=diff" \
        "$WORKDIR/palette.png"

    ${pkgs.ffmpeg}/bin/ffmpeg -y -v error -i "$RAW" -i "$WORKDIR/palette.png" \
        -lavfi "fps=15,scale=iw:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3" \
        "$OUTPUT"

    ${pkgs.libnotify}/bin/notify-send "Record GIF" "Saved $OUTPUT"

    # Opens the folder, not the file — no portable "reveal and select
    # this one file" concept exists here, only "open this path" (a
    # directory opens in whatever the desktop's default file manager is).
    #
    # gio open, not xdg-open: confirmed on a real run via the systemd
    # journal (screenshot-listener's own log) that xdg-open's desktop-
    # detection fails silently in this service's environment and falls
    # all the way through its DE-detection cases to trying to launch
    # nothing but WEB BROWSERS for a directory — never even reaching the
    # step that would have read the actual default-app registry
    # (confirmed separately, working correctly: `xdg-mime query default
    # inode/directory` → org.gnome.Nautilus.desktop). `gio open` reads
    # that exact same registry directly, without xdg-open's desktop-
    # detection step to fail. Backgrounded so a slow-to-start file
    # manager never delays this script's own exit.
    ${pkgs.glib.bin}/bin/gio open "$RECORDING_DIR" &
  '';

  # Stops an in-progress recording. SIGINT is wl-screenrec's finalise-and-exit
  # path — it flushes the encoder and closes the container — so this is a clean
  # stop rather than an abort. record-gif then does the GIF conversion.
  record-gif-stop = pkgs.writeShellScriptBin "record-gif-stop" ''
    set -uo pipefail

    PIDFILE="''${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR not set}/kartoza-record-gif.pid"

    if [[ ! -f "$PIDFILE" ]]; then
        ${pkgs.libnotify}/bin/notify-send "Record GIF" "No recording in progress"
        exit 0
    fi

    PID=$(cat "$PIDFILE")
    if ${pkgs.procps}/bin/ps -p "$PID" >/dev/null 2>&1; then
        kill -INT "$PID"
        ${pkgs.libnotify}/bin/notify-send "Record GIF" "Finishing GIF…"
    else
        rm -f "$PIDFILE"
        ${pkgs.libnotify}/bin/notify-send "Record GIF" "No recording in progress"
    fi
  '';

  # One key instead of two: start if nothing is recording, stop if something
  # is — bind THIS to a single shortcut rather than record-gif-trigger and
  # record-gif-stop to separate ones. Same PIDFILE-liveness check record-gif
  # and record-gif-stop already each do their own version of, reused here to
  # decide which of the two existing commands to run rather than duplicating
  # either one. Starts via capture-trigger (not record-gif directly), for
  # the same keybind-cannot-grab-the-seat reason every other trigger in this
  # file does — see the workaround note below.
  record-gif-toggle = pkgs.writeShellScriptBin "record-gif-toggle" ''
    set -uo pipefail

    PIDFILE="''${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR not set}/kartoza-record-gif.pid"

    if [[ -f "$PIDFILE" ]] && ${pkgs.procps}/bin/ps -p "$(cat "$PIDFILE")" >/dev/null 2>&1; then
        exec ${record-gif-stop}/bin/record-gif-stop
    else
        exec ${capture-trigger}/bin/capture-trigger record "''${1:-0}"
    fi
  '';

  # --- COSMIC keybind → screenshot workaround (pop-os/cosmic-epoch#2481) ---
  #
  # COSMIC has a bug where an interactive Wayland seat grab (slurp) launched
  # *directly* from a custom keybind fires the shortcut but cannot grab the
  # seat, so region selection silently does nothing. The fix decouples the
  # keypress from the capture:
  #
  #   keybind → screenshot-trigger  (writes a token to a FIFO, no grab)
  #             screenshot-listener (long-lived session service, owns the grab)
  #                               → screenshot-satty (existing wrapper)
  #
  # Because the listener runs as a normal persistent Wayland client in the
  # graphical session, slurp grabs the seat correctly.

  # The FIFO and unit keep their "screenshot" names even though they now also
  # carry GIF recording. Renaming them would leave the previous generation's
  # screenshot-listener running against the same path until the next logout,
  # with both units fighting over one FIFO — not worth the churn.
  fifoPath = "\${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR not set}/kartoza-screenshot.trigger";

  # Persistent listener: owns the FIFO and performs the actual capture.
  # Both capture paths (screenshot and GIF) run slurp, so both need this.
  screenshot-listener = pkgs.writeShellScriptBin "screenshot-listener" ''
    set -uo pipefail

    FIFO="${fifoPath}"

    ${pkgs.coreutils}/bin/rm -f "$FIFO"
    ${pkgs.coreutils}/bin/mkfifo -m 600 "$FIFO"
    trap '${pkgs.coreutils}/bin/rm -f "$FIFO"' EXIT

    while true; do
        # Blocks until a trigger opens and writes the pipe. The payload is
        # "ACTION<TAB>ARG<TAB>WAYLAND_DISPLAY<TAB>DBUS_SESSION_BUS_ADDRESS"
        # so the capture targets the caller's live session regardless of
        # this service's start-time env. ARG is the mode for screenshots,
        # the duration for recordings. DBUS_SESSION_BUS_ADDRESS exists for
        # record-gif's `gio open` on the Recordings folder when it is
        # done — GUI app activation over D-Bus needs the session bus, and
        # a systemd --user service is not guaranteed to already have it
        # any more than it was guaranteed to already have WAYLAND_DISPLAY.
        if IFS=$'\t' read -r action arg wl dbus < "$FIFO"; then
            [ -n "''${wl:-}" ] && export WAYLAND_DISPLAY="$wl"
            [ -n "''${dbus:-}" ] && export DBUS_SESSION_BUS_ADDRESS="$dbus"
            # Detached so a slow Satty annotation — or a long recording —
            # never delays the next trigger.
            case "''${action:-screenshot}" in
                screenshot)
                    ${screenshot-satty}/bin/screenshot-satty "''${arg:-region}" &
                    ;;
                record)
                    ${record-gif}/bin/record-gif "''${arg:-0}" &
                    ;;
                *)
                    ${pkgs.libnotify}/bin/notify-send "Capture" \
                      "Unknown action: ''${action}"
                    ;;
            esac
        fi
    done
  '';

  # Shared keybind target: only pokes the listener, never grabs the seat itself.
  # screenshot-trigger and record-gif-trigger are thin wrappers over this.
  capture-trigger = pkgs.writeShellScriptBin "capture-trigger" ''
    set -uo pipefail

    FIFO="${fifoPath}"
    ACTION="''${1:?usage: capture-trigger ACTION ARG}"
    ARG="''${2:-}"

    if [ ! -p "$FIFO" ]; then
        ${pkgs.libnotify}/bin/notify-send "Capture" \
          "Listener not running — check: systemctl --user status screenshot-listener"
        exit 1
    fi

    # Cap the write so a wedged listener can never hang the compositor's
    # keybind handler.
    if ! ${pkgs.coreutils}/bin/timeout 2 \
        ${pkgs.bash}/bin/bash -c 'printf "%s\t%s\t%s\t%s\n" "$1" "$2" "$3" "$4" > "$5"' \
        _ "$ACTION" "$ARG" "''${WAYLAND_DISPLAY:-}" "''${DBUS_SESSION_BUS_ADDRESS:-}" "$FIFO"; then
        ${pkgs.libnotify}/bin/notify-send "Capture" "Could not reach capture listener"
        exit 1
    fi
  '';

  # Keybind target for screenshots. Name and CLI deliberately unchanged — the
  # Ctrl+4 binding lives in the user's COSMIC settings, not in this repo.
  screenshot-trigger = pkgs.writeShellScriptBin "screenshot-trigger" ''
    set -uo pipefail
    exec ${capture-trigger}/bin/capture-trigger screenshot "''${1:-region}"
  '';

  # Keybind target for GIF recording. Optional arg = duration in seconds;
  # 0 (the default) records until record-gif-stop.
  record-gif-trigger = pkgs.writeShellScriptBin "record-gif-trigger" ''
    set -uo pipefail
    exec ${capture-trigger}/bin/capture-trigger record "''${1:-0}"
  '';
in
{
  config = mkIf cfg.enable {
    # COSMIC core applications (many bundled with services.desktopManager.cosmic)
    # COSMIC packages from nixpkgs-unstable via overlay
    environment.systemPackages =
      (with cosmicPkgs; [
        # COSMIC core applications
        cosmic-edit # Text editor
        # cosmic-files # File manager - replaced by nautilus
        cosmic-term # Terminal
        cosmic-store # App store
        cosmic-screenshot # Screenshot tool
        cosmic-player # Media player
        cosmic-reader # PDF reader
        cosmic-monitor # System monitor (new in COSMIC 1.1)
        tasks # COSMIC to-do app (formerly named cosmic-tasks)

        # COSMIC icons and theming
        cosmic-icons
      ])
      # The cosmic-ext-* community extensions and applets used to be here.
      # They all source build, so they are their own bundle now:
      # desktop-environments-cosmic-extensions.
      ++ [
        # Kartoza-branded App Library panel button icon. hiPrio so it
        # wins the path conflict with whatever cosmic-applets ships at
        # share/icons/hicolor/scalable/apps/com.system76.CosmicAppLibrary.svg.
        (lib.hiPrio kartoza-cosmic-app-library-icon)
      ]
      ++ (with pkgs; [
        # COSMIC keybind → screenshot workaround (pop-os/cosmic-epoch#2481).
        # Cosmic-specific glue kept here; the generic capture tools it calls
        # (grim/slurp/satty/libnotify) now live in desktop-base.nix.
        screenshot-satty # Takes screenshot and opens in Satty for annotation
        screenshot-listener # Persistent service that owns the grab (see below)
        capture-trigger # Shared FIFO poke used by both triggers below
        screenshot-trigger # Keybind target: pokes the listener via a FIFO
        # GIF recording — same slurp-then-capture shape as the screenshot path,
        # so it goes through the same listener to get a working seat grab.
        record-gif # slurp region → wlgif → GIF in ~/Videos/Recordings
        record-gif-trigger # Keybind target: start a recording
        record-gif-stop # Keybind target: finish the GIF (SIGINT to wlgif)
        record-gif-toggle # Keybind target: one key, start/stop both
      ]);

    # Screenshot listener (COSMIC keybind workaround, pop-os/cosmic-epoch#2481).
    # Long-lived per-user service that owns the grim/slurp/satty grab so it
    # succeeds; the Ctrl+4 keybind only pokes it via a FIFO (screenshot-trigger).
    systemd.user.services.screenshot-listener = {
      description = "COSMIC screenshot listener (FIFO-triggered capture via screenshot-satty)";
      documentation = [ "https://github.com/pop-os/cosmic-epoch/issues/2481" ];
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${screenshot-listener}/bin/screenshot-listener";
        Restart = "always";
        RestartSec = 2;
        Slice = "session.slice";
      };
    };

    # Exclude some default COSMIC packages if desired
    # environment.cosmic.excludePackages = with pkgs; [
    #   cosmic-design-demo
    # ];
  };
}
