#!/usr/bin/env bash
#
# adduser — add a user account to this flake and wire it into chosen hosts.
#
# Asks for a username, full name, a password (hashed into the user's .nix,
# never stored in plaintext), and SSH keys fetched from a GitHub username —
# the same steps the installer's user wizard takes — then which hosts to add
# the user to. Each chosen host's default.nix gains an import of the new
# users/<name>.nix. The whole logic lives in utils/adduser.py.
#
# GISNIX_ROOT is gisnix's own tree (registry + the installer helpers this
# reuses); the CURRENT DIRECTORY is the target flake whose users/ and hosts/
# get edited — so this works from a downstream flake, not only a gisnix
# checkout. See utils/lib/hostconfig.py for the same split.
set -uo pipefail

GISNIX_ROOT="${GISNIX_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export GISNIX_ROOT

case "${1:-}" in
  -h | --help)
    awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
    exit 0
    ;;
esac

[ -d hosts ] || {
  echo "adduser: no hosts/ here — run this from your flake's own repo root" >&2
  exit 1
}

exec python3 "$GISNIX_ROOT/utils/adduser.py" "$@"
