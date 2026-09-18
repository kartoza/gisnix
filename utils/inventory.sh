#!/usr/bin/env bash
#
# inventory — a fleet overview: one line per host, read-only.
#
# Ported from the personal-servers flake, adapted to this repo's registry.
# There is no cloud provider here — every machine is bare metal someone owns —
# so the "provisioned" column of the original is replaced by owner and address,
# and the local machine is inspected directly rather than over SSH.
#
# Read-only and idempotent; safe to run any time. For a deep single-host
# report use `check <host>`; for pre-rebuild safety checks use
# `preflight <host>`.
#
# Usage:
#   kz inventory                 # every host in hosts/fleet.nix
#   kz inventory abyss waterfall # just these
#   kz inventory --help
#
# Requires SSH access as each host's sshUser. Hosts with no lanAddress and no
# overlay entry simply show as unreachable — that is information, not an error.
set -uo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[38;2;88;150;50m'
YELLOW=$'\033[38;2;240;230;74m'
BLUE=$'\033[38;2;147;176;35m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
NC=$'\033[0m'

HOSTS=()
while (($# > 0)); do
  case "$1" in
    -h | --help)
      awk 'NR>1 && /^# shellcheck/ {next} NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
      exit 0
      ;;
    -*)
      echo "${RED}Unknown flag: $1${NC}"
      exit 1
      ;;
    *) HOSTS+=("$1") ;;
  esac
  shift
done

[[ -f ./hosts/fleet.nix ]] || {
  echo "${RED}run from the repo root (hosts/fleet.nix missing).${NC}"
  exit 1
}

NIX=(nix --extra-experimental-features 'nix-command flakes')

# Read one field for one host straight out of the registry. Importing the file
# directly rather than evaluating the flake keeps this fast: `nix eval .#…`
# would pull in nixpkgs and every host configuration just to read a string.
host_field() { # $1=host $2=field $3=default
  "${NIX[@]}" eval --raw --impure --expr \
    "let h = (import ./hosts/fleet.nix).hosts.$1; v = h.$2 or null;
     in if v == null then \"$3\" else v" 2>/dev/null || echo "$3"
}

if [[ ${#HOSTS[@]} -eq 0 ]]; then
  mapfile -t HOSTS < <(
    "${NIX[@]}" eval --impure --raw --expr \
      'builtins.concatStringsSep "\n" (builtins.attrNames (import ./hosts/fleet.nix).hosts)' 2>/dev/null
  )
fi

[[ ${#HOSTS[@]} -gt 0 ]] || {
  echo "${RED}could not read the host list from hosts/fleet.nix${NC}"
  exit 1
}

ENV_NAME="$(tr -d '[:space:]' < environment.txt 2>/dev/null || echo prod)"
SELF="$(hostname -s 2>/dev/null || echo '')"

ssh_run() {
  local u="$1" h="$2"
  shift 2
  ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
    "${u}@${h}" "$@"
}

echo
echo "${BOLD}Fleet inventory${NC}   ${DIM}environment: ${ENV_NAME}   ·   this machine: ${SELF:-unknown}${NC}"
echo "${DIM}──────────────────────────────────────────────────────────────────────────────────${NC}"
printf "${BOLD}%-10s %-12s %-9s %-15s %-6s %s${NC}\n" \
  "HOST" "ROLE" "OWNER" "ADDRESS" "SSH" "STATE"
echo "${DIM}──────────────────────────────────────────────────────────────────────────────────${NC}"

for host in "${HOSTS[@]}"; do
  [[ -n "$host" ]] || continue
  role="$(host_field "$host" role workstation)"
  owner="$(host_field "$host" owner '?')"
  addr="$(host_field "$host" lanAddress '')"
  ssh_user="$(host_field "$host" sshUser "$USER")"
  deploy="$(host_field "$host" deploy ssh)"

  addr_disp="${addr:-${DIM}—${NC}}"

  # Query locally when this IS the host — SSH to yourself needs the daemon
  # reachable on its own address, which is exactly what a laptop on wifi
  # cannot rely on.
  if [[ "$host" == "$SELF" ]]; then
    sshc="${DIM}self${NC}"
    state="$(systemctl is-system-running 2>/dev/null || echo unknown)"
    failed="$(systemctl --failed --no-legend --plain --no-pager 2>/dev/null | grep -cE '\.service' || true)"
  elif [[ "$deploy" == "none" ]]; then
    sshc="${DIM}—${NC}"
    state="vm-only"
    failed=0
  elif ssh_run "$ssh_user" "${addr:-$host}" true 2>/dev/null; then
    sshc="${GREEN}up${NC}"
    state="$(ssh_run "$ssh_user" "${addr:-$host}" 'systemctl is-system-running' 2>/dev/null || echo unknown)"
    failed="$(ssh_run "$ssh_user" "${addr:-$host}" 'systemctl --failed --no-legend --plain --no-pager' 2>/dev/null | grep -cE '\.service' || true)"
  else
    sshc="${RED}down${NC}"
    state=""
    failed=0
  fi
  failed="${failed:-0}"

  if [[ -z "$state" ]]; then
    svc="${DIM}unreachable${NC}"
  elif [[ "$state" == "vm-only" ]]; then
    svc="${DIM}not deployed — kz ${host}-vm${NC}"
  elif [[ "$state" == "running" && "$failed" -eq 0 ]]; then
    svc="${GREEN}all healthy${NC}"
  elif [[ "$failed" -gt 0 ]]; then
    svc="${RED}${failed} failed unit(s) — run: check ${host}${NC}"
  else
    svc="${YELLOW}${state}${NC}"
  fi

  printf "%-10s %-12s %-9s %-24b %-15b %b\n" \
    "$host" "$role" "$owner" "$addr_disp" "$sshc" "$svc"
done

echo "${DIM}──────────────────────────────────────────────────────────────────────────────────${NC}"
echo "${BLUE}💁${NC}  One host in depth: ${BOLD}check <host>${NC}   ·   before rebuilding: ${BOLD}preflight <host>${NC}   ·   push config: ${BOLD}update <host>${NC}"
