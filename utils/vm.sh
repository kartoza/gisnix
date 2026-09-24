#!/usr/bin/env bash
#
# vm — run a host's configuration in a QEMU virtual machine, quick boot.
#
#   gisnix vm                  # this machine, quick boot
#   gisnix vm myhost           # another host, quick boot
#   gisnix vm --list           # which hosts can be run
#
# QEMU loads the kernel and initrd DIRECTLY. GRUB never runs and Plymouth
# never shows. Headless, and the fastest way to answer "does this
# configuration come up at all".
#
# Does not touch the machine you are sitting at. The login is whatever the
# host's users declare; a VM built from a host with disk encryption will ask
# for the passphrase exactly as the real one does.
#
# --boot (full GRUB/Plymouth boot, was here previously) is disabled for now
# — see memory project_virtiofsd_zfs_eperm.md: its disk-image build hits a
# virtiofsd/ZFS EPERM that panics the inner builder VM on this fleet. The
# root cause and fix are known (an overlay forcing virtiofsd
# --inode-file-handles=never) but not yet applied. To test an actual
# install instead of previewing a boot theme, use `gisnix test-install`.
set -uo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$REPO_ROOT" ] || {
  echo "vm: not inside a git repository" >&2
  exit 1
}
cd "$REPO_ROOT" || exit 1

DIM=$'\033[2m'
NC=$'\033[0m'

hosts() { find hosts -mindepth 2 -maxdepth 2 -name config.nix -printf '%h\n' | xargs -n1 basename | sort; }

usage() {
  awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
}

HOST=""

while [ $# -gt 0 ]; do
  case "$1" in
    --boot | --full)
      echo "vm: --boot is disabled for now — its disk-image build is known-broken on this fleet." >&2
      echo "    See memory project_virtiofsd_zfs_eperm.md. Use 'gisnix test-install' to test a real install." >&2
      exit 1
      ;;
    --quick) ;; # already the only mode
    --list)
      hosts
      exit 0
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      echo "vm: unknown option: $1" >&2
      exit 1
      ;;
    *)
      [ -z "$HOST" ] || {
        echo "vm: one host at a time, got '$HOST' and '$1'" >&2
        exit 1
      }
      HOST="$1"
      ;;
  esac
  shift
done

# No host means this machine, the way `gisnix update` and `gisnix configure` resolve it.
if [ -z "$HOST" ]; then
  self="$(hostname -s 2>/dev/null || true)"
  if hosts | grep -qx "$self"; then
    HOST="$self"
    printf '  %sno host given — defaulting to this machine: %s%s\n' "$DIM" "$HOST" "$NC"
  else
    echo "vm: this machine (${self:-unknown}) is not a host here." >&2
    echo "    Name one: $(hosts | tr '\n' ' ')" >&2
    exit 1
  fi
fi

hosts | grep -qx "$HOST" || {
  echo "vm: no hosts/$HOST/config.nix" >&2
  echo "    Known hosts: $(hosts | tr '\n' ' ')" >&2
  exit 1
}

printf '  %squick boot — kernel loaded directly, no GRUB or Plymouth.%s\n' "$DIM" "$NC"
echo

exec nix run ".#${HOST}-vm"
