#!/usr/bin/env bash
#
# keyboard-diagrams — redraw the keyboard layout diagrams from their source.
#
# gisnix ships one kanata mechanism (software/services/device/input/
# kanata-config.nix) applied to whichever board a host has; only the
# `kanataLayout` knob ("us" or "pt") changes the geometry and chord output.
# docs/scripts/generate-keyboard-diagrams.py draws the base and navigation
# layers for both, straight from the same key tables the module uses, so
# changing a layout and re-running this keeps the docs in step. Nothing
# here touches a keyboard — it only reads configuration and writes SVGs.
#
# A downstream flake with its own per-host extras — a second kanata
# instance, a different chord set, a firmware-driven board — draws its own
# diagrams for those; this only covers the mechanism gisnix itself ships.
#
#   gisnix keyboard-diagrams
#
# The docs build runs this too; this is for when you have just changed the
# layout and want to see the picture without building the whole site.
set -uo pipefail

GREEN=$'\033[38;2;88;150;50m'
RED=$'\033[0;31m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
NC=$'\033[0m'

OPEN=1
case "${1:-}" in
  --no-open) OPEN=0 ;;
  -h | --help)
    awk 'NR>1 && /^# shellcheck/ {next} NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
    exit 0
    ;;
  "") ;;
  *)
    echo "${RED}unknown argument: $1${NC}" >&2
    exit 1
    ;;
esac

[ -f flake.nix ] || {
  echo "${RED}✗ run from the repo root${NC}"
  exit 1
}

OUT_DIR=docs/assets/keyboards

if ! python3 docs/scripts/generate-keyboard-diagrams.py; then
  echo "${RED}✗ generator failed — see above${NC}"
  exit 1
fi

COUNT="$(find "$OUT_DIR" -maxdepth 1 -name '*.svg' 2> /dev/null | wc -l)"
echo "${GREEN}✓ keyboard diagrams regenerated${NC}  ${DIM}${COUNT} SVGs under ${OUT_DIR}/${NC}"

# Opening the folder is the point of running this by hand: you changed a
# layout and want to look at the result. Skipped with --no-open so the docs
# build and any CI use can call it without spawning a file manager.
if [ "$OPEN" -eq 1 ]; then
  if command -v xdg-open > /dev/null 2>&1; then
    echo "${DIM}  opening ${OUT_DIR}/…${NC}"
    # Detached and silenced: a file manager left attached to this process
    # keeps the command running until the window is closed.
    xdg-open "$OUT_DIR" > /dev/null 2>&1 &
    disown 2> /dev/null || true
  else
    echo "${DIM}  xdg-open not available — the SVGs are in ${OUT_DIR}/${NC}"
  fi
fi
