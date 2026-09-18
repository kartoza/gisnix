#!/usr/bin/env bash
#
# fleet-status — a one-line-per-host dashboard of who is reachable.
#
# This runs on every dev-shell entry, so it is built for speed rather than
# depth: hosts are probed concurrently with a short timeout and it reports
# reachability only. Anything that needs an SSH round trip — unit health, pool
# state, generation — belongs in `inventory` or `check`, which you run when
# you actually want to wait for it.
#
# A host with no lanAddress cannot be probed at all. That is not a failure:
# the roaming laptops have no stable address, and once they are on the NetBird
# overlay their names resolve through NetBird's DNS instead. They are shown as
# "no address" rather than "down", because those mean different things.
#
#   fleet-status            # the dashboard
#   fleet-status --quiet    # only the summary line
set -uo pipefail

GREEN=$'\033[38;2;88;150;50m'
RED=$'\033[0;31m'
YELLOW=$'\033[38;2;240;230;74m'
CYAN=$'\033[38;2;83;161;203m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
NC=$'\033[0m'

ROOT="${NIX_CONFIG_ROOT:-$PWD}"
[ -f "$ROOT/hosts/fleet.nix" ] || exit 0

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

NIX=(nix --extra-experimental-features 'nix-command flakes')

# One eval for the whole registry rather than one per host per field: this is
# on the shell-entry path, and nine separate `nix eval` calls is most of a
# second of latency for information that fits in one string.
REGISTRY="$(
  # shellcheck disable=SC2016  # a Nix expression: nothing here is a shell var
  cd "$ROOT" && "${NIX[@]}" eval --impure --raw --expr '
    let
      fleet = (import ./hosts/fleet.nix).hosts;
      # Fields are separated by "|", not a tab. Tab is whitespace, so bash
      # `read` collapses runs of it and a host with no lanAddress would
      # silently shift every following column. Nix has no \xNN escape, so a
      # real unit separator cannot be written here as a literal.
      sep = "|";
      line =
        n: h:
        builtins.concatStringsSep sep [
          n
          (if h.lanAddress == null then "" else h.lanAddress)
          h.role
          h.owner
          h.deploy
        ];
    in builtins.concatStringsSep "\n" (builtins.attrValues (builtins.mapAttrs line fleet))
  ' 2>/dev/null
)" || exit 0
[ -n "$REGISTRY" ] || exit 0

SELF="$(hostname -s 2>/dev/null || true)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Probe concurrently. ping -W1 -c1 bounds each to about a second, so the whole
# fleet resolves in roughly that, not nine times that.
while IFS='|' read -r name addr role owner deploy; do
  [ -n "$name" ] || continue
  {
    if [ "$name" = "$SELF" ]; then
      state=self
    elif [ "$deploy" = "none" ]; then
      state=vm
    elif [ -z "$addr" ]; then
      state=noaddr
    elif ping -c1 -W1 "$addr" > /dev/null 2>&1; then
      state=up
    else
      state=down
    fi
    printf '%s|%s|%s|%s|%s\n' "$name" "$addr" "$role" "$owner" "$state" \
      > "$TMP/$name"
  } &
done <<< "$REGISTRY"
wait

up=0 down=0 other=0 total=0
rows=""
for f in "$TMP"/*; do
  [ -f "$f" ] || continue
  IFS='|' read -r name addr role owner state < "$f"
  total=$((total + 1))
  case "$state" in
    up)
      mark="${GREEN}●${NC}"
      note="${DIM}${addr}${NC}"
      up=$((up + 1))
      ;;
    self)
      mark="${CYAN}◆${NC}"
      note="${DIM}this machine${NC}"
      up=$((up + 1))
      ;;
    down)
      mark="${RED}○${NC}"
      note="${DIM}no answer at ${addr}${NC}"
      down=$((down + 1))
      ;;
    noaddr)
      mark="${YELLOW}◌${NC}"
      note="${DIM}no fixed address${NC}"
      other=$((other + 1))
      ;;
    vm)
      mark="${DIM}·${NC}"
      note="${DIM}vm only${NC}"
      other=$((other + 1))
      ;;
  esac
  rows="${rows}$(printf '  %b %-11s %-12s %-9s %b' "$mark" "$name" "$role" "$owner" "$note")\n"
done

if [ "$QUIET" -eq 0 ]; then
  printf '  %sFleet%s  %sreachability only; inventory shows unit health%s\n' \
    "$BOLD" "$NC" "$DIM" "$NC"
  printf '%b' "$rows"
fi
printf '  %s%d up%s · %s%d down%s · %d other, of %d hosts\n' \
  "$GREEN" "$up" "$NC" "$RED" "$down" "$NC" "$other" "$total"
