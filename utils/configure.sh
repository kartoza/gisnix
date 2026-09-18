#!/usr/bin/env bash
#
# configure — turn a host's software bundles on and off, from a menu.
#
#   kz configure                       # pick a host, then tick the bundles
#   kz configure atoll                 # straight to atoll's bundles
#   kz configure atoll --list          # show what it takes, change nothing
#   kz configure atoll --enable desktop-gis
#   kz configure atoll --disable terminal-ai,desktop-games
#   kz configure atoll --set base,desktop-browsers --locale za-en
#   kz configure atoll --enable security --dry-run
#
# The menu is built from the bundle registry — every bundle.json under
# software/ — and not from what the host's config.nix happens to list today.
# A bundle added this morning is therefore on the menu this afternoon, and a
# host that has never heard of it says so explicitly rather than by omission.
#
# It rewrites the `bundles = [ … ];` block and leaves everything else in the
# file alone. Nothing is written until the diff has been shown and confirmed,
# and never at all if the result fails to parse.
#
# The reference for what each bundle contains is `kz bundles`, or
# docs/references/bundles.md.
#
# WHY THIS IS A WRAPPER
#
# The command manifest builds each command from one shell file, so a command
# has to start in shell. The work itself — reading Nix, preserving comments,
# rendering the block — is in utils/configure.py, beside the library it
# shares with `kz create-host` (utils/lib/hostconfig.py). Duplicating any of
# that into shell would give the two commands separate ideas of what a
# config.nix should look like, which is the drift the bundle system exists to
# prevent.
set -uo pipefail

case "${1:-}" in
  -h | --help)
    exec python3 utils/configure.py --help
    ;;
esac

[ -d software ] || {
  echo "configure: run from the repo root" >&2
  exit 1
}

exec python3 utils/configure.py "$@"
