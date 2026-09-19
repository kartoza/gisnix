#!/usr/bin/env bash
#
# vm — run a host's configuration in a QEMU virtual machine.
#
#   gisnix vm                  # this machine, quick boot
#   gisnix vm waterfall        # another host, quick boot
#   gisnix vm abyss --boot     # the full boot: UEFI/GRUB, then Plymouth
#   gisnix vm --list           # which hosts can be run
#
# TWO VARIANTS, AND WHY BOTH EXIST
#
#   quick (default)  QEMU loads the kernel and initrd DIRECTLY. GRUB never
#                    runs and Plymouth never shows. Headless, and the fastest
#                    way to answer "does this configuration come up at all".
#
#   --boot           Boots through the bootloader, graphically: GRUB with its
#                    theme, then the Plymouth splash. This is the one for
#                    working on the boot EXPERIENCE — branding, resolution,
#                    the splash — without rebooting real hardware.
#                    See profiles/boot-vm.nix for the overrides; the writable
#                    qcow is wiped on every run, so a stale disk cannot
#                    silently re-run the previous configuration.
#
# Neither touches the machine you are sitting at. The login is whatever the
# host's users declare; a VM built from a host with disk encryption will ask
# for the passphrase exactly as the real one does.
set -uo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$REPO_ROOT" ] || {
  echo "vm: not inside a git repository" >&2
  exit 1
}
cd "$REPO_ROOT" || exit 1

BOLD=$'\033[1m'
DIM=$'\033[2m'
NC=$'\033[0m'

hosts() { find hosts -mindepth 2 -maxdepth 2 -name config.nix -printf '%h\n' | xargs -n1 basename | sort; }

usage() {
  awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
}

VARIANT=vm
HOST=""

while [ $# -gt 0 ]; do
  case "$1" in
    --boot | --full) VARIANT=bootvm ;;
    --quick) VARIANT=vm ;;
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
    printf '  %sno host given — defaulting to this machine: %s%s%s\n' "$DIM" "$NC$BOLD" "$HOST" "$NC"
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

if [ "$VARIANT" = bootvm ]; then
  printf '  %sfull boot — UEFI/GRUB, then Plymouth. Graphical window.%s\n' "$DIM" "$NC"
else
  printf '  %squick boot — kernel loaded directly, no GRUB or Plymouth.%s\n' "$DIM" "$NC"
  printf '  %s%s for the full boot sequence.%s\n' "$DIM" "gisnix vm $HOST --boot" "$NC"
fi
echo

exec nix run ".#${HOST}-${VARIANT}"
