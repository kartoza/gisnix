#!/usr/bin/env bash
#
# check-bundle-eval — evaluate the example host with every non-opt-in bundle
# enabled, so evaluation-time failures in bundles the example host does not
# normally take are caught in CI rather than on someone's install.
#
# Why this exists: the build gate builds the example host, but the example host
# enables only a minimal bundle set — so an unfree or insecure package in, say,
# desktop-gis (googleearth-pro is both) sails through and only fails at
# `sudo setup` on real hardware. unfree/insecure/assertion errors all throw at
# EVAL, so evaluating a max-bundle host is a cheap, comprehensive net for that
# whole class. Eval only — nothing is built.
#
# Opt-in bundles are excluded on purpose: they are the heavy or deliberately
# rough ones (QGIS source builds, the vintage QGIS pins whose own descriptions
# warn they "may no longer evaluate"), not what a normal install takes.
# One-of choices (kernel, locale) are scalars, not list entries, so they are
# excluded too.
#
# Usage: utils/check-bundle-eval.sh [host]   (default: example)
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
HOST="${1:-example}"
CFG="hosts/${HOST}/config.nix"
NIX=(nix --extra-experimental-features "nix-command flakes")

[[ -f "$CFG" ]] || { echo "no $CFG"; exit 1; }

# Always restore the config, even on error or Ctrl-C. This is the safety the
# ad-hoc version lacked — an interrupt used to leave the config half-edited.
trap 'git checkout -- "$CFG" 2>/dev/null || true' EXIT

mapfile -t BUNDLES < <(python3 - <<'PY'
import sys
sys.path.insert(0, "docs/scripts")
import bundles
for b in bundles.load():
    if b.get("optIn") or b.get("selection") == "one-of":
        continue
    print(b["name"])
PY
)
[[ ${#BUNDLES[@]} -gt 0 ]] || { echo "could not read the bundle registry"; exit 1; }

echo "enabling ${#BUNDLES[@]} non-opt-in bundles on '${HOST}' and evaluating..."
for name in "${BUNDLES[@]}"; do
  # Uncomment `# "name"` -> `"name"`; the escaped name guards against any
  # regex-special characters in a bundle name.
  esc=$(printf '%s' "$name" | sed 's/[.[\*^$/]/\\&/g')
  sed -i "s/^\(\s*\)# \"${esc}\"/\1\"${esc}\"/" "$CFG"
done

if "${NIX[@]}" eval --raw ".#nixosConfigurations.${HOST}.config.system.build.toplevel.drvPath" >/dev/null 2>eval-err.txt; then
  echo "OK: '${HOST}' with all non-opt-in bundles evaluates cleanly."
  rm -f eval-err.txt
else
  echo "FAIL: evaluation failed with all non-opt-in bundles enabled —"
  echo "an unfree/insecure package needs allow-listing, or a bundle has an"
  echo "eval error. This is the class that breaks installs. Error:"
  tail -n 20 eval-err.txt
  rm -f eval-err.txt
  exit 1
fi
