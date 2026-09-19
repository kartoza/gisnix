#!/usr/bin/env bash
# shellcheck disable=SC2154  # palette/helpers come from the inlined prelude
#
# check — one host in depth: is it reachable, where is it in its boot, are its
# pools healthy, are any units failed.
#
# Generalised from waterfall-status.sh. That script knew one machine's LAN and
# tailnet addresses, its pool names and its unlock port. All of that now comes
# from hosts/fleet.nix, so this answers the same questions for any host.
#
#   gisnix check                # this machine
#   gisnix check waterfall
#
# The interesting case is a host that pings but has no SSH: on a machine with
# an encrypted root that usually means it is sitting at the initrd unlock
# prompt, which looks identical to "still booting" unless you check the
# unlock port. This does.
#
# Read-only. For the whole fleet at a glance use `inventory`.
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

ADDR="$(f_field "$HOST" lanAddress '')"
ROLE="$(f_field "$HOST" role workstation)"
OWNER="$(f_field "$HOST" owner '?')"
PORT="$(f_field "$HOST" initrdSshPort '')"
DEPLOY="$(f_field "$HOST" deploy ssh)"
SELF="$(hostname -s 2>/dev/null || true)"

echo
echo "${f_bold}${HOST}${f_nc}  ${f_dim}${ROLE} · ${OWNER} · ${ADDR:-no fixed address}${f_nc}"
echo "${f_dim}──────────────────────────────────────────────────────────────${f_nc}"

# Local host: everything is answerable without the network at all.
if [ "$HOST" = "$SELF" ]; then
  echo "  ${f_green}this machine${f_nc}"
  # Same payload either way — locally it is just fed to a local bash.
  probe() { bash -s; }
elif [ "$DEPLOY" = "none" ]; then
  echo "  ${f_dim}not deployed — run it as a VM:  gisnix ${HOST}-vm${f_nc}"
  exit 0
else
  TARGET="$(f_reach "$HOST" 2> /dev/null)" || TARGET=""
  if [ -n "$TARGET" ]; then
    echo "  ${f_green}UP${f_nc}  ${f_dim}SSH answering at ${TARGET}${f_nc}"
    probe() { f_ssh "$HOST" bash -s; }
  else
    # No SSH. Distinguish the three ways that happens, because the remedy for
    # each is completely different.
    if [ -n "$PORT" ] && [ -n "$ADDR" ] && f_port_open "$ADDR" "$PORT"; then
      echo "  ${f_yellow}AT THE UNLOCK PROMPT${f_nc}  ${f_dim}cold boot, waiting for the pool passphrase${f_nc}"
      echo "    ${f_bold}gisnix unlock ${HOST}${f_nc}"
      exit 0
    fi
    if [ -n "$ADDR" ] && ping -c1 -W2 "$ADDR" > /dev/null 2>&1; then
      echo "  ${f_yellow}BOOTING${f_nc}  ${f_dim}pings but no SSH yet — retry shortly${f_nc}"
      exit 0
    fi
    echo "  ${f_red}DOWN${f_nc}  ${f_dim}no answer — suspended, powered off, or you are off its network${f_nc}"
    if [ -n "$(f_field "$HOST" macAddress '')" ]; then
      echo "    ${f_bold}gisnix wake ${HOST}${f_nc}   ${f_dim}(from the same LAN)${f_nc}"
    fi
    exit 1
  fi
fi

# The remote login shell is fish on these hosts, so the payload is piped
# through bash explicitly rather than relying on the login shell's syntax.
probe << 'REMOTE' 2>/dev/null || echo "  ${f_dim}(no detail — is your key loaded? try ssh-add)${f_nc}"
echo
echo "  system state:  $(systemctl is-system-running 2>/dev/null || echo unknown)"
echo "  uptime:       $(uptime -p 2>/dev/null | sed 's/^up //')"
echo "  generation:   $(readlink /run/current-system 2>/dev/null | sed 's|.*/||')"

failed=$(systemctl --failed --no-legend --plain --no-pager 2>/dev/null | grep -cE '\.service' || true)
if [ "${failed:-0}" -gt 0 ]; then
  echo
  echo "  FAILED UNITS (${failed}):"
  systemctl --failed --no-legend --plain --no-pager 2>/dev/null | sed 's/^/    /'
fi

if command -v zpool >/dev/null 2>&1; then
  echo
  echo "  pools:"
  zpool list -o name,size,alloc,health 2>/dev/null | sed 's/^/    /'
  locked=$(zfs get -H -o value keystatus 2>/dev/null | grep -c unavailable || true)
  if [ "${locked:-0}" -gt 0 ]; then
    echo
    echo "    ${locked} dataset(s) locked — unlock on the host with: unlock-data"
  fi
fi

echo
echo "  disk:"
df -h --output=target,pcent,avail / /home 2>/dev/null | sed 's/^/    /'
REMOTE

echo "${f_dim}──────────────────────────────────────────────────────────────${f_nc}"
echo "${f_dim}  whole fleet:  gisnix inventory   ·   push config:  gisnix update ${HOST}${f_nc}"
