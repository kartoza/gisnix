#!/usr/bin/env bash
#
# gc — free up /nix by deleting old generations and collecting garbage.
#
# update.sh already offers this after a successful rebuild, but that's no
# use when the build itself fails first (a full store can't even complete a
# `nix build`) or when you just want space back without rebuilding anything.
# This is the same cleanup, standalone.
#
# Usage:
#   gisnix gc              # keep the last 10 generations, confirm, then collect
#   gisnix gc --keep 3     # keep fewer generations before collecting
#   gisnix gc --yes        # skip the confirmation prompt
set -uo pipefail

GREEN=$'\033[38;2;88;150;50m'
BLUE=$'\033[38;2;147;176;35m'
RED=$'\033[0;31m'
BOLD=$'\033[1m'
NC=$'\033[0m'

info() { echo "  ${BLUE}💁  $1${NC}"; }
ok() { echo "  ${GREEN}✅  $1${NC}"; }
err() { echo "  ${RED}❌  $1${NC}"; }
step() { echo; echo "${BOLD}${GREEN}▸ $1${NC}"; }

KEEP=10
YES=0

while (($# > 0)); do
  case "$1" in
    -h | --help)
      awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
      exit 0
      ;;
    --keep)
      KEEP="${2:?--keep needs a number}"
      shift
      ;;
    --yes) YES=1 ;;
    *)
      err "unknown argument: $1"
      exit 1
      ;;
  esac
  shift
done

step "before"
df -h /nix 2>/dev/null || df -h /

if ((!YES)); then
  if command -v gum >/dev/null 2>&1; then
    gum confirm "Delete generations older than the last ${KEEP} and collect garbage?" --default=false || {
      info "cancelled — nothing was changed"
      exit 0
    }
  else
    read -r -p "Delete generations older than the last ${KEEP} and collect garbage? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || {
      info "cancelled — nothing was changed"
      exit 0
    }
  fi
fi

step "cleaning up"
sudo nix-env --delete-generations "+${KEEP}" --profile /nix/var/nix/profiles/system
sudo nix-collect-garbage
ok "cleanup complete"

step "after"
df -h /nix 2>/dev/null || df -h /
