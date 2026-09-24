#!/usr/bin/env bash
#
# test-boot — thin passthrough so `gisnix test-boot` shows up in the
# command table and cheat-sheet. Relaunches the ISO/disk `test-install`
# already built, without rebuilding — see flake.nix's `test-boot` app for
# the actual logic (same reasoning as test-install.sh for why it isn't
# reimplemented here).
#
#   gisnix test-boot
set -uo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$REPO_ROOT" ] || {
  echo "test-boot: not inside a git repository" >&2
  exit 1
}
cd "$REPO_ROOT" || exit 1

exec nix --extra-experimental-features "nix-command flakes" run ".#test-boot" -- "$@"
