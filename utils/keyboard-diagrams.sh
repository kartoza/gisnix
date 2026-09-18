#!/usr/bin/env bash
#
# keyboard-diagrams — redraw every keyboard layout diagram from its source.
#
# abyss has four keyboards, each configured a different way, and each with its
# own generator:
#
#   Razer Ornata, Framework built-in  kanata, hosts/abyss/kanata-keyboard.nix
#   Krom Kernel Pro                   keyd,   hosts/abyss/krom-keyboard.nix
#   MoErgo Glove80                    its own firmware (stock binds; kanata
#                                     does the remapping on the host)
#   Dygma Sonsei                      the keyboard's own memory, exported to
#                                     hosts/abyss/sonsei-layout.json
#
# Every diagram is derived from those sources rather than drawn by hand, so
# changing a layout and re-running this keeps the docs in step. Nothing here
# touches a keyboard — it only reads configuration and writes SVGs.
#
#   kz keyboard-diagrams      (or: kz keyboard-diagrams)
#
# The docs build runs these too; this is for when you have just changed a
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

OUT_DIR=docs/assets/abyss

fail=0
run() { # <label> <script>
  local label="$1" script="$2"
  if [ ! -f "$script" ]; then
    echo "  ${DIM}· ${label} — ${script} not present, skipped${NC}"
    return 0
  fi
  echo "${BOLD}▶ ${label}${NC}"
  if python3 "$script"; then
    echo "  ${GREEN}✓${NC} ${label}"
  else
    echo "  ${RED}✗${NC} ${label}"
    fail=1
  fi
}

run "kanata hosts (every host with a kanata-keyboard.nix — abyss, porto, atoll)" docs/scripts/generate-keyboard-diagrams.py
run "MoErgo Glove80" docs/scripts/generate-glove80-diagrams.py
run "Dygma Sonsei" docs/scripts/generate-sonsei-diagrams.py

echo
if [ "$fail" -ne 0 ]; then
  echo "${RED}✗ some generators failed — see above${NC}"
  exit "$fail"
fi

COUNT="$(find docs/assets -maxdepth 2 -name '*keyboard*.svg' 2> /dev/null | wc -l)"
echo "${GREEN}✓ all keyboard diagrams regenerated${NC}  ${DIM}${COUNT} keyboard SVGs under docs/assets/${NC}"

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
