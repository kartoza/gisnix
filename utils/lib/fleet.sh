# shellcheck shell=bash
#
# Shared fleet plumbing for the operator commands.
#
# Inlined into each command by mkCommandApp's `prelude` (see flake.nix)
# rather than sourced: writeShellApplication wraps a single file, so a
# relative `source` would resolve against the store path of the wrapper.
#
# Everything here reads hosts/fleet.nix. These helpers exist so that
# suspend, wake, check and unlock stop being four scripts that each know one
# machine's IP and MAC by heart — which is what waterfall-suspend.sh,
# waterfall-wake.sh, waterfall-status.sh and waterfall-unlock.sh were.

# shellcheck disable=SC2034
f_red=$'\033[0;31m'
# shellcheck disable=SC2034
f_green=$'\033[38;2;88;150;50m'
# shellcheck disable=SC2034
f_yellow=$'\033[38;2;240;230;74m'
# shellcheck disable=SC2034
f_blue=$'\033[38;2;147;176;35m'
# shellcheck disable=SC2034
f_dim=$'\033[2m'
# shellcheck disable=SC2034
f_bold=$'\033[1m'
# shellcheck disable=SC2034
f_nc=$'\033[0m'

# shellcheck disable=SC2329  # used only by some of the commands that inline this
f_die() {
  echo "${f_red}✗ $1${f_nc}" >&2
  exit 1
}

_F_NIX=(nix --extra-experimental-features 'nix-command flakes')

# shellcheck disable=SC2329  # used only by some of the commands that inline this
f_require_repo() {
  [ -f ./hosts/fleet.nix ] ||
    f_die "run from the repo root (hosts/fleet.nix missing)"
}

# One field for one host. Importing the registry directly rather than
# evaluating the flake keeps this fast: `nix eval .#…` pulls in nixpkgs and
# every host configuration just to read a string.
# shellcheck disable=SC2329  # used only by some of the commands that inline this
f_field() { # <host> <field> <default>
  "${_F_NIX[@]}" eval --raw --impure --expr \
    "let h = (import ./hosts/fleet.nix).hosts.$1 or {}; v = h.$2 or null;
     in if v == null then \"$3\" else toString v" 2>/dev/null || printf '%s' "$3"
}

# One host name per line, INCLUDING a trailing newline on the last.
#
# concatStringsSep does not terminate the final line, and `while read` does
# not run its body for a line without one — so f_known silently could not see
# whichever host sorted last. `kz unlock waterfall` refused waterfall and then
# listed waterfall among the known hosts, because the check read the list line
# by line and the message printed it whole.
#
# shellcheck disable=SC2329  # used only by some of the commands that inline this
f_hosts() {
  "${_F_NIX[@]}" eval --impure --raw --expr \
    'builtins.concatStringsSep "\n" (builtins.attrNames (import ./hosts/fleet.nix).hosts) + "\n"' 2>/dev/null
}

# shellcheck disable=SC2329  # used only by some of the commands that inline this
f_known() { # <host> — true if it is in the registry
  # `|| [ -n "$h" ]` handles a final line with no newline. f_hosts terminates
  # its output now, so this is belt and braces — but it is the half that fails
  # silently, by omitting a host rather than erroring, so it is worth keeping.
  local h
  while IFS= read -r h || [ -n "$h" ]; do
    [ "$h" = "$1" ] && return 0
  done < <(f_hosts)
  return 1
}

# Resolve the argument, defaulting to this machine when it is one of ours.
# shellcheck disable=SC2329  # used only by some of the commands that inline this
f_resolve_host() { # [host]
  if [ -n "${1:-}" ]; then
    f_known "$1" || f_die "'$1' is not a host in hosts/fleet.nix.
  known hosts: $(f_hosts | tr '\n' ' ')"
    printf '%s' "$1"
    return 0
  fi
  local self
  self="$(hostname -s 2>/dev/null || true)"
  f_known "$self" && {
    printf '%s' "$self"
    return 0
  }
  f_die "no host given, and this machine (${self:-unknown}) is not in the registry.
  known hosts: $(f_hosts | tr '\n' ' ')"
}

# shellcheck disable=SC2329  # used only by some of the commands that inline this
f_port_open() { # <host> <port>
  timeout 3 bash -c "</dev/tcp/$1/$2" 2> /dev/null
}

# The gateway answering is our proxy for "on the same LAN segment". Wake-on-LAN
# and initrd unlocking both need that; neither works across the overlay.
# shellcheck disable=SC2329  # used only by some of the commands that inline this
f_on_lan() {
  local gw
  gw="$("${_F_NIX[@]}" eval --raw --impure --expr \
    '(import ./hosts/fleet.nix).peers.router.lanAddress or ""' 2>/dev/null)"
  [ -n "$gw" ] || return 1
  ping -c1 -W1 "$gw" > /dev/null 2>&1
}

# First address where the host's sshd answers. Prefers the registry address,
# then the bare name, which is what the overlay resolver will answer for.
# shellcheck disable=SC2329  # used only by some of the commands that inline this
f_reach() { # <host>
  local host="$1" addr
  addr="$(f_field "$host" lanAddress '')"
  for candidate in ${addr:+"$addr"} "$host"; do
    if f_port_open "$candidate" 22; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

# shellcheck disable=SC2329  # used only by some of the commands that inline this
f_ssh() { # <host> <command…>
  local host="$1" user target
  shift
  user="$(f_field "$host" sshUser "$USER")"
  target="$(f_reach "$host")" || return 1
  ssh -o ConnectTimeout=5 -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new "${user}@${target}" "$@"
}

# Refuse early on a host that has no hardware to act on. Every fleet command
# needs this and they were each about to grow their own copy; the VM hint is
# the useful next step, so it belongs with the check.
# shellcheck disable=SC2329  # used only by some of the commands that inline this
f_require_deployable() { # <host>
  if [ "$(f_field "$1" deploy ssh)" = "none" ]; then
    echo "${f_yellow}$1 is not deployed to hardware (deploy = \"none\").${f_nc}" >&2
    echo "${f_dim}Run it as a VM instead:${f_nc}  ${f_bold}kz $1-vm${f_nc}" >&2
    exit 0
  fi
}

# Reachability with an explanation. ssh's own error says "connection refused",
# which does not distinguish a sleeping host from one that has no address in
# the registry at all — and the remedies are completely different.
# shellcheck disable=SC2329  # used only by some of the commands that inline this
f_require_reachable() { # <host>
  f_reach "$1" > /dev/null 2>&1 && return 0
  f_die "cannot reach $1 over SSH.
  Where is it?  kz check $1
  A host with no lanAddress in hosts/fleet.nix is only reachable once it is on
  the overlay network."
}
