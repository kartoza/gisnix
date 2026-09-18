#!/usr/bin/env bash
#
# env — show or switch this checkout's build environment.
#
# environment.txt holds one word, `dev` or `prod`, and profiles/development.nix
# keys off it. In dev the firewall is relaxed, root SSH and password auth are
# permitted, and development-only services are wired up; prod is what the fleet
# actually runs.
#
# The personal-servers flake pairs this with a .env file of deployment
# credentials. This repo has none — every secret is in agenix — so the only
# thing to manage here is the mode.
#
#   kz env            # show the current mode and what it changes
#   kz env dev     # switch to development
#   kz env prod    # switch to production
#   kz env toggle  # flip to the other one
#
# WATCH OUT: an interactive TUI menu used to write `dev` here merely for being
# opened. That menu has been removed, but if a host has unexpectedly relaxed
# its firewall, this file is still the first thing to check.
#
# Switching only edits the file. Nothing takes effect until you rebuild.
set -uo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[38;2;88;150;50m'
YELLOW=$'\033[38;2;240;230;74m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
NC=$'\033[0m'

FILE=environment.txt

[ -f flake.nix ] || {
  echo "${RED}✗ run from the repo root${NC}"
  exit 1
}

current() { tr -d '[:space:]' < "$FILE" 2> /dev/null || echo prod; }

describe() {
  local mode="$1"
  if [ "$mode" = "dev" ]; then
    echo "  ${YELLOW}${BOLD}dev${NC} — development"
    echo "${DIM}    · firewall relaxed${NC}"
    echo "${DIM}    · root SSH login permitted${NC}"
    echo "${DIM}    · SSH password authentication permitted${NC}"
    echo "${DIM}    · development-only services enabled${NC}"
    echo
    echo "  ${YELLOW}Do not leave a deployed host in dev.${NC}"
  else
    echo "  ${GREEN}${BOLD}prod${NC} — production"
    echo "${DIM}    · firewall enforced${NC}"
    echo "${DIM}    · key-only SSH, no root login${NC}"
    echo "${DIM}    · this is what the fleet runs${NC}"
  fi
}

WANT="${1:-}"
NOW="$(current)"

case "$WANT" in
  '')
    echo
    echo "${BOLD}Build environment${NC}  ${DIM}${FILE}${NC}"
    echo
    describe "$NOW"
    echo
    echo "${DIM}  switch with:  kz env ${NOW/dev/prod}${NC}"
    exit 0
    ;;
  -h | --help)
    awk 'NR>1 && /^# shellcheck/ {next} NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
    exit 0
    ;;
  toggle) [ "$NOW" = "dev" ] && WANT=prod || WANT=dev ;;
  dev | prod) ;;
  *)
    echo "${RED}✗ unknown mode '${WANT}' — expected dev, prod or toggle${NC}"
    exit 1
    ;;
esac

if [ "$WANT" = "$NOW" ]; then
  echo "${DIM}already ${WANT} — nothing to do${NC}"
  exit 0
fi

printf '%s\n' "$WANT" > "$FILE"
echo "${BOLD}${NOW} → ${WANT}${NC}"
echo
describe "$WANT"
echo
echo "${DIM}  environment.txt is tracked — commit the change if it is deliberate.${NC}"
echo "${DIM}  apply it with:  kz update${NC}"
