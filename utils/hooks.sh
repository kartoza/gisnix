#!/usr/bin/env bash
#
# hooks — install this repo's pre-commit hooks into the working tree.
#
# Unlike the personal-servers flake, which hand-writes its hook body, this repo
# drives the pre-commit framework from .pre-commit-config.yaml. That config is
# the source of truth for which checks run; this script only wires it into
# .git/hooks and reports what it installed.
#
# Idempotent — re-run any time, and after changing .pre-commit-config.yaml.
#
# Usage:
#   kz hooks            # install
#   kz hooks --all   # install, then sweep every file in the repo
set -uo pipefail

CYAN=$'\033[38;2;74;170;160m'
GREEN=$'\033[38;2;88;150;50m'
YELLOW=$'\033[38;2;240;230;74m'
RED=$'\033[0;31m'
BOLD=$'\033[1m'
NC=$'\033[0m'

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "${RED}✗ not a git repository — run this from the repo root${NC}"
  exit 1
}

command -v pre-commit >/dev/null 2>&1 || {
  echo "${RED}✗ pre-commit is not on PATH${NC}"
  echo "${YELLOW}  enter the dev shell first:  nix develop${NC}"
  exit 1
}

echo "${BOLD}${CYAN}▶ installing pre-commit hooks${NC}"
pre-commit install || exit 1

echo
echo "${BOLD}Active hooks, from .pre-commit-config.yaml:${NC}"
grep -oE '^\s+- id: [a-z0-9._-]+' .pre-commit-config.yaml 2>/dev/null |
  sed "s/.*id: /  ${GREEN}•${NC} /" || echo "  (could not read .pre-commit-config.yaml)"

echo
if [ "${1:-}" = "--all" ]; then
  echo "${YELLOW}▶ sweeping every file in the repo — this reformats as it goes${NC}"
  pre-commit run --all-files
  exit $?
fi

echo "${BOLD}Next:${NC}"
echo "  ${GREEN}•${NC} hooks now run on every ${BOLD}git commit${NC}"
echo "  ${GREEN}•${NC} sweep the whole repo:      ${BOLD}kz hooks --all${NC}"
echo "  ${GREEN}•${NC} one hook only:             ${BOLD}pre-commit run <id>${NC}"
echo "  ${GREEN}•${NC} full static analysis:      ${BOLD}kz lint${NC}"
echo
echo "${YELLOW}  Do not use --no-verify: the hooks include the secret scan.${NC}"
