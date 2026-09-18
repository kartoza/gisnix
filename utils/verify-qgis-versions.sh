#!/usr/bin/env bash
# Verify every entry in software/desktop/gis/qgis-versions.json: the pinned
# nixpkgs tarball fetches with the cached sha256, and the named attr
# evaluates to the QGIS version the manifest promises.
#
# Run from anywhere inside the repo. Downloads each pinned nixpkgs into the
# store once (~1 GB total for all 23) — those paths are then reused whenever
# a version is enabled, so nothing is wasted. Expect the vintage 1.8/2.x
# entries to be the only plausible failures (ancient nixpkgs vs modern nix).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
manifest=software/desktop/gis/qgis-versions.json
fail=0
for series in $(jq -r 'keys[]' "$manifest" | sort -t. -k1,1n -k2,2n); do
  rev=$(jq -r ".\"$series\".rev" "$manifest")
  sha=$(jq -r ".\"$series\".sha256" "$manifest")
  attr=$(jq -r ".\"$series\".attr" "$manifest")
  want=$(jq -r ".\"$series\".version" "$manifest")
  got=$(nix-instantiate --eval --strict -E "
    let pkgs = import (fetchTarball {
      url = \"https://github.com/NixOS/nixpkgs/archive/$rev.tar.gz\";
      sha256 = \"$sha\";
    }) { system = builtins.currentSystem; };
    in (builtins.parseDrvName pkgs.$attr.name).version" 2>&1 | tail -1 | tr -d '"')
  if [ "$got" = "$want" ]; then
    echo "ok   qgis $series -> $got ($attr)"
  else
    echo "FAIL qgis $series expected $want, got: $got"
    fail=1
  fi
done
exit $fail
