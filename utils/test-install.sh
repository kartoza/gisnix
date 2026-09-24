#!/usr/bin/env bash
#
# test-install — thin passthrough so `gisnix test-install` shows up in the
# command table and cheat-sheet. The actual QEMU/OVMF build-and-boot logic
# stays in flake.nix's `test-install` app, not reimplemented here — that
# script needs Nix-interpolated store paths (OVMF's firmware files) a
# plain utils/*.sh can't get for free, and it already works.
#
#   gisnix test-install
set -uo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$REPO_ROOT" ] || {
  echo "test-install: not inside a git repository" >&2
  exit 1
}
cd "$REPO_ROOT" || exit 1

exec nix --extra-experimental-features "nix-command flakes" run ".#test-install" -- "$@"
