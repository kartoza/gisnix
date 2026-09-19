#!/usr/bin/env bash
# shellcheck disable=SC2154  # palette/helpers come from the inlined prelude
#
# suspend — park a host in suspend-to-RAM.
#
# Generalised from waterfall-suspend.sh, which knew one machine's addresses by
# heart. The host is now looked up in hosts/fleet.nix, so this works for any
# host in the registry.
#
#   gisnix suspend             # this machine, if it is in the registry
#   gisnix suspend waterfall
#
# ZFS keys and the session survive in RAM, so resuming needs no unlock. Waking
# needs `gisnix wake` from the same LAN segment — see that command for why.
set -uo pipefail

# The SC2154 disable at the top of this file is because the colour palette
# and helper functions live in utils/lib/fleet.sh, which the manifest's
# `prelude` inlines ahead of this script at build time. Linting the file on
# its own cannot see them. The disable is scoped to SC2154, so genuine
# unassigned-variable typos still fail the build.

[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && {
  awk 'NR>1 && /^# shellcheck/ {next} NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
  exit 0
}

f_require_repo
HOST="$(f_resolve_host "${1:-}")" || exit 1
f_require_deployable "$HOST"

TARGET="$(f_reach "$HOST")" || f_die "cannot reach ${HOST} on SSH.
  It may already be asleep, powered off, or you may be off its network.
  Check with:  gisnix check ${HOST}"

echo "${f_bold}Suspending ${HOST}${f_nc}  ${f_dim}(via ${TARGET})${f_nc}"

# The connection dropping as the host goes to sleep is the expected outcome,
# not a failure, so its exit status tells us nothing.
f_ssh "$HOST" sudo systemctl suspend || true

sleep 3
if ping -c1 -W2 "$TARGET" > /dev/null 2>&1; then
  echo "${f_yellow}Still answering ping — the suspend may not have taken.${f_nc}"
  echo "${f_dim}  something may be inhibiting it; check: systemd-inhibit --list${f_nc}"
  exit 1
fi

MAC="$(f_field "$HOST" macAddress '')"
echo "${f_green}✓ ${HOST} is asleep${f_nc}"
if [ -n "$MAC" ]; then
  echo "${f_dim}  wake it with:  gisnix wake ${HOST}   (same LAN only)${f_nc}"
else
  echo "${f_yellow}  no macAddress in hosts/fleet.nix — this host cannot be woken remotely.${f_nc}"
fi
