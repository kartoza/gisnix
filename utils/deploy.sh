#!/usr/bin/env bash
#
# deploy — create a Hetzner cloud server and install a host onto it.
#
#   gisnix deploy island            # create the machine, then install
#   gisnix deploy island --dry-run  # show what would be created
#   gisnix deploy --list            # hosts that have Hetzner parameters
#
# THIS IS THE CLOUD PATH, AND IT COSTS MONEY. `hcloud server create` makes a
# billable machine before nixos-anywhere installs onto it, using the flags in
# hosts/<name>/server.nix.
#
# NOT TO BE CONFUSED WITH `gisnix install`
#
#   gisnix deploy   creates a machine that does not exist yet, at Hetzner
#   gisnix install  takes over a machine that DOES exist and is booted from a
#               live USB — a laptop on the VPN, say. No cloud provider is
#               involved and nothing is billed
#
# Both end in nixos-anywhere; they differ entirely in where the machine comes
# from. See docs/developer/remote-install.md for the second.
#
# This is a front door for `nix run .#<host>-deploy`, which is generated per
# host from allHosts and so cannot be a manifest row of its own — the same
# reason `gisnix vm` exists.
set -uo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$REPO_ROOT" ] || {
  echo "deploy: not inside a git repository" >&2
  exit 1
}
cd "$REPO_ROOT" || exit 1

BOLD=$'\033[1m'
DIM=$'\033[2m'
RED=$'\033[38;2;200;70;60m'
NC=$'\033[0m'

say() { printf '  %s\n' "$*"; }
die() {
  printf '  %s✗%s %s\n' "$RED" "$NC" "$*" >&2
  exit 1
}

usage() {
  awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
}

deployable() {
  find hosts -mindepth 2 -maxdepth 2 -name server.nix -printf '%h\n' \
    | xargs -n1 basename | sort
}

HOST=""
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run | -n) DRY_RUN=1 ;;
    --list)
      deployable
      exit 0
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*) die "unknown option: $1" ;;
    *)
      [ -z "$HOST" ] || die "one host at a time, got '$HOST' and '$1'"
      HOST="$1"
      ;;
  esac
  shift
done

[ -n "$HOST" ] || {
  usage
  exit 1
}

[ -f "hosts/$HOST/server.nix" ] || die "hosts/$HOST/server.nix does not exist.
    That file holds the \`hcloud server create\` flags, so a host without one
    cannot be created at Hetzner. If this is a physical machine you are
    taking over, you want \`gisnix install\` instead — see
    docs/developer/remote-install.md.
    Hosts that can be deployed: $(deployable | tr '\n' ' ')"

printf '\n  %sDeploy %s to Hetzner%s\n' "$BOLD" "$HOST" "$NC"
printf '  %s%s%s\n' "$DIM" "$(printf '─%.0s' {1..66})" "$NC"
say ""
say "${BOLD}This creates a billable machine.${NC} hcloud parameters:"
grep -oP '"\K[^"]+' "hosts/$HOST/server.nix" | sed 's/^/    /'
say ""
say "${DIM}Then nixos-anywhere installs .#$HOST onto it.${NC}"
say ""

if [ "$DRY_RUN" = 1 ]; then
  say "${DIM}Would run:  nix run .#$HOST-deploy${NC}"
  say ""
  printf '  %s✓%s --dry-run: nothing was created.\n' $'\033[38;2;88;150;50m' "$NC"
  exit 0
fi

exec nix run ".#$HOST-deploy"
