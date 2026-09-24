#!/usr/bin/env bash
#
# makeiso — build the installer ISO, named exactly the way
# .github/workflows/release.yml names it for a GitHub Release:
#
#   dist/gisnix-installer.iso           stable name, always this
#   dist/gisnix-installer-vX.Y.Z.iso    hard link, this build's exact version
#   ...and a .sha256 next to each.
#
# The version comes from ./VERSION (kept in step with CHANGELOG.md's top
# entry per the project's version-bump rule) — this is a LOCAL build, not
# a tagged release, so nothing here creates or pushes a git tag.
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$REPO_ROOT" ] || {
  echo "makeiso: not inside a git repository" >&2
  exit 1
}
cd "$REPO_ROOT" || exit 1

usage() {
  awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  "") ;;
  *)
    echo "makeiso: unknown argument: $1" >&2
    exit 1
    ;;
esac

[ -f VERSION ] || {
  echo "makeiso: no VERSION file at repo root" >&2
  exit 1
}
version="v$(<VERSION)"

echo "Building installer ISO for ${version}..."
nix build .#nixosConfigurations.installer.config.system.build.isoImage --print-build-logs

iso=$(find result/iso -maxdepth 1 -name '*.iso' | head -n1)
[ -n "$iso" ] || {
  echo "makeiso: no .iso found under result/iso" >&2
  exit 1
}

mkdir -p dist
cp -f "$iso" dist/gisnix-installer.iso
# Hard link, not a second copy — same file, no extra disk.
ln -f dist/gisnix-installer.iso "dist/gisnix-installer-${version}.iso"
sha256sum dist/gisnix-installer.iso >dist/gisnix-installer.iso.sha256
sha256sum "dist/gisnix-installer-${version}.iso" >"dist/gisnix-installer-${version}.iso.sha256"

size_bytes=$(stat -c%s dist/gisnix-installer.iso)
size_human=$(numfmt --to=iec --suffix=B "$size_bytes")

echo
echo "Built:"
echo "  dist/gisnix-installer.iso                (${size_human})"
echo "  dist/gisnix-installer-${version}.iso"
echo "  + matching .sha256 files"

# GitHub rejects a release asset over 2GB outright — installer.nix's own
# isoImage.storeContents comment documents hitting this already.
if [ "$size_bytes" -gt 2147483648 ]; then
  echo
  echo "WARNING: ${size_human} is over GitHub's 2GB release-asset limit." >&2
  echo "         A tag push will build fine but the release upload will be rejected." >&2
fi
