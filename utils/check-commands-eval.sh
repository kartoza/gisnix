#!/usr/bin/env bash
#
# check-commands-eval — evaluate every operator-command app the flake mints from
# commands.json. Each `apps.<system>.<name>` carries its deps as runtimeInputs,
# so a row naming a nixpkgs attribute that does not exist (or any other eval
# error in a command definition) throws here — before it ships as a broken
# `gisnix <cmd>`. Eval only (no build), so this is cheap enough for a pre-push
# hook; the same script can gate CI. See check-example-builds.sh for the build.
set -euo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
NIX=(nix --extra-experimental-features "nix-command flakes")
system="$(nix eval --impure --raw --expr builtins.currentSystem 2>/dev/null || echo x86_64-linux)"

echo "evaluating every command app (apps.${system}.*)..."
# Forcing each app's `program` resolves its derivation — which pulls in its
# deps, so an unknown nixpkgs attribute fails right here.
if "${NIX[@]}" eval ".#apps.${system}" \
   --apply 'as: builtins.deepSeq (builtins.mapAttrs (_: a: a.program) as) (builtins.attrNames as)' \
   >/dev/null; then
  echo "✓ all command apps evaluate"
else
  echo "✗ a command app failed to evaluate — check the deps/definition in commands.json" >&2
  exit 1
fi
