#!/usr/bin/env bash
#
# check-example-builds — BUILD the example host toplevel, the same thing a real
# `sudo setup` install builds. eval is not build: derivations validated only at
# build time (notably the kanata .kdb via `kanata --check`) pass eval and fail
# here. Heavy (a full system build), so this is a pre-PUSH hook, not pre-commit,
# and the same script gates CI (build-hosts.yml / release.yml).
set -euo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
NIX=(nix --extra-experimental-features "nix-command flakes")

echo "building example host toplevel (install-equivalent)..."
if "${NIX[@]}" build --no-link --print-out-paths \
   .#nixosConfigurations.example.config.system.build.toplevel; then
  echo "✓ example host builds"
else
  echo "✗ example host failed to build — this is what breaks a bare-metal install" >&2
  exit 1
fi
