#!/usr/bin/env bash
#
# test — run the flake's checks.
#
# `nix flake check` evaluates every nixosConfiguration, builds every
# writeShellApplication (each is shellcheck-gated at build time) and runs the
# per-host integration tests in tests/. This is the same gate CI runs.
#
# It is heavy: the host tests boot NixOS VMs. Expect minutes, not seconds, and
# a lot of disk. To check a single host instead:
#
#   nix build .#checks.x86_64-linux.<hostname>
#
# Usage:
#   kz test              # everything
#   kz test -L        # stream build logs, useful when one hangs
set -uo pipefail

echo "▶ nix flake check   (host evals + per-app shellcheck + NixOS VM tests)"
echo "  This builds VMs and can take several minutes."
echo
exec nix flake check "$@"
