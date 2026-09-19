#!/usr/bin/env bash
# shellcheck disable=SC2154  # palette/helpers come from the inlined prelude
#
# wake — wake a suspended host with a Wake-on-LAN magic packet.
#
# Generalised from a machine-specific wake script. The MAC comes from
# hosts/fleet.nix, so a host without one is reported as "cannot be woken"
# rather than failing obscurely.
#
#   gisnix wake myhost
#
# Magic packets are LAN broadcasts. They cannot traverse the NetBird overlay
# or any other tunnel, so this only works from the same network segment — the
# command checks that first rather than sending into the void.
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

MAC="$(f_field "$HOST" macAddress '')"
[ -n "$MAC" ] || f_die "${HOST} has no macAddress in hosts/fleet.nix, so it cannot be
  woken remotely. Add its wired NIC MAC to the registry if it should be."

ADDR="$(f_field "$HOST" lanAddress '')"
[ -n "$ADDR" ] || f_die "${HOST} has no lanAddress in hosts/fleet.nix, so there is no
  address to watch for it coming back."

f_on_lan || f_die "you are not on the home LAN (the gateway does not answer), so a
  magic packet cannot reach ${HOST} from here."

echo "${f_bold}Waking ${HOST}${f_nc}  ${f_dim}magic packet to ${MAC}${f_nc}"
wakeonlan "$MAC" > /dev/null

for _ in $(seq 1 15); do
  if ping -c1 -W2 "$ADDR" > /dev/null 2>&1; then
    echo "${f_green}✓ ${HOST} is awake${f_nc}  ${f_dim}answering at ${ADDR}${f_nc}"
    exit 0
  fi
  sleep 2
done

echo "${f_yellow}No answer after ~30s.${f_nc}"
echo "${f_dim}  If it was suspended, this should have worked — check the BIOS has${f_nc}"
echo "${f_dim}  'Resume by PCI-E/LAN' enabled and ErP disabled.${f_nc}"
PORT="$(f_field "$HOST" initrdSshPort '')"
if [ -n "$PORT" ]; then
  echo "${f_dim}  If it was powered off rather than suspended, booting stops at the${f_nc}"
  echo "${f_dim}  pool unlock prompt:  gisnix unlock ${HOST}${f_nc}"
fi
exit 1
