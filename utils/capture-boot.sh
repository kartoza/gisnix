#!/usr/bin/env bash
# Capture the QEMU bootvm window once per second so Claude has a frame-
# by-frame record of GRUB -> Plymouth -> greeter transitions.
#
# Usage:
#   1. Launch the QEMU window in another terminal:
#        gisnix minimal-bootvm
#   2. As soon as the QEMU window appears, run:
#        bash utils/capture-boot.sh
#      You'll be prompted (via slurp) to drag-select the QEMU window
#      region.  After that, screenshots fire every second until Ctrl-C
#      or the 3 min cap.
#   3. Frames land in:
#        untracked_screenshots/boot-<timestamp>/frame-NNNN.png
#
# Optional flags:
#   --geom W,H+X+Y  Skip slurp and use a fixed region.  Useful for
#                   re-runs at the same window position.
#   --interval N    Seconds between frames (default 1).
#   --max N         Max frames to capture (default 180).
#
# This script is a Wayland-native tool (uses grim + slurp).  It works on
# COSMIC / sway / Hyprland / niri etc.; X11 sessions are not supported.

set -euo pipefail

# ---------- defaults --------------------------------------------------
interval=1
max_frames=180
geom=""

# ---------- arg parsing -----------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --geom)     geom="$2"; shift 2 ;;
    --interval) interval="$2"; shift 2 ;;
    --max)      max_frames="$2"; shift 2 ;;
    -h|--help)
      sed -n '/^# Capture/,/^$/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

# ---------- preflight --------------------------------------------------
if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
  echo "ERROR: WAYLAND_DISPLAY not set — this script needs a Wayland session." >&2
  exit 1
fi
for cmd in grim slurp; do
  command -v "$cmd" >/dev/null || { echo "ERROR: $cmd not found in PATH." >&2; exit 1; }
done

# ---------- region selection ------------------------------------------
if [[ -z "$geom" ]]; then
  echo "Drag-select the QEMU window in the slurp overlay..." >&2
  geom=$(slurp -f '%w,%h+%x+%y' 2>/dev/null) || {
    echo "ERROR: slurp cancelled or failed." >&2
    exit 1
  }
  echo "Region: $geom"
  echo "Reuse this geometry on the next run with:  --geom '$geom'"
fi

# slurp's '%w,%h+%x+%y' is W,H+X+Y — grim wants 'X,Y WxH'.
# Translate so the user can either paste back from slurp output OR pass
# in a 'X,Y WxH' string directly.
if [[ "$geom" =~ ^([0-9]+),([0-9]+)\+([0-9]+)\+([0-9]+)$ ]]; then
  W=${BASH_REMATCH[1]}; H=${BASH_REMATCH[2]}
  X=${BASH_REMATCH[3]}; Y=${BASH_REMATCH[4]}
  grim_geom="${X},${Y} ${W}x${H}"
elif [[ "$geom" =~ ^([0-9]+),([0-9]+)\ ([0-9]+)x([0-9]+)$ ]]; then
  grim_geom="$geom"
else
  echo "ERROR: --geom must be 'W,H+X+Y' (slurp form) or 'X,Y WxH' (grim form)." >&2
  exit 1
fi

# ---------- output dir ------------------------------------------------
ts=$(date +%Y%m%d-%H%M%S)
out_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/untracked_screenshots"
out_dir="${out_root}/boot-${ts}"
mkdir -p "$out_dir"
echo "Capturing to: $out_dir"
echo "Interval: ${interval}s, max ${max_frames} frames."
echo "Ctrl-C to stop early."
echo

# ---------- capture loop ----------------------------------------------
start=$(date +%s)
trap 'echo; echo "Stopped at frame $i."; exit 0' INT TERM

for i in $(seq -f '%04g' 1 "$max_frames"); do
  elapsed=$(( $(date +%s) - start ))
  printf '\rframe %s  (t+%3ds)' "$i" "$elapsed"
  grim -g "$grim_geom" "${out_dir}/frame-${i}.png"
  sleep "$interval"
done

echo
echo "Done — captured $max_frames frames over ~$((max_frames * interval)) s."
