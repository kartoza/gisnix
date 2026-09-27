#!/usr/bin/env bash
#
# set-timezone — set this host's clock by picking a Region/City.
#
# Writes a `timeZone` override into hosts/<host>/config.nix; the change takes
# effect on your next `gisnix update` (via profiles/locale-overrides.nix). This
# is a focused shortcut for the timezone axis of `gisnix locale`, sharing the
# same editor (utils/lib/locale_edit.py) so the two never disagree.
#
# The editor and manifest come from gisnix's own tree (GISNIX_ROOT); the host's
# config.nix is in the caller's flake (the cwd) — so this works from a
# downstream flake, not only a gisnix checkout.
set -uo pipefail

GISNIX_ROOT="${GISNIX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export GISNIX_ROOT

case "${1:-}" in
  -h | --help)
    awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
    exit 0
    ;;
esac

RED=$'\033[0;31m'
GREEN=$'\033[38;2;88;150;50m'
DIM=$'\033[2m'
NC=$'\033[0m'

[ -d hosts ] || {
  echo "${RED}set-timezone: no hosts/ here — run this from your flake's own repo root${NC}" >&2
  exit 1
}

EDIT=(python3 "$GISNIX_ROOT/utils/lib/locale_edit.py")

hosts() { find hosts -mindepth 2 -maxdepth 2 -name config.nix -printf '%h\n' | xargs -n1 basename | sort; }

# Resolve the host the same way `gisnix update`/`locale` do: this machine.
self="$(hostname -s 2>/dev/null || true)"
if hosts | grep -qx "$self"; then
  HOST="$self"
else
  echo "${RED}set-timezone: this machine (${self:-unknown}) is not a host in this flake.${NC}" >&2
  echo "    Known hosts: $(hosts | tr '\n' ' ')" >&2
  exit 1
fi
CONFIG="hosts/$HOST/config.nix"

tz=$(timedatectl list-timezones 2>/dev/null | gum filter --header "Timezone — type a city or region") || exit 0
[ -n "$tz" ] || exit 0

"${EDIT[@]}" "$CONFIG" set timeZone "$tz"
echo "  ${GREEN}✓ ${HOST}: timeZone = \"$tz\"${NC}"
echo "  ${DIM}Applied on your next:  gisnix update${NC}"
