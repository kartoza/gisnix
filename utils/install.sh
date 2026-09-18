#!/usr/bin/env bash
#
# install — put a host's configuration onto a machine booted from a live ISO.
#
#   kz install foobar root@10.100.0.42     # install, WIPING that machine's disk
#   kz install foobar root@10.100.0.42 --dry-run
#   kz install foobar tim@foobar --seed    # after reboot: clone the flake there
#
# THE WORKFLOW THIS SERVES
#
#   1. the owner boots the machine from a live ISO (any Linux with sshd)
#   2. the owner joins the VPN, so it is reachable on the virtual LAN
#   3. the owner adds the admin's public key to the LIVE system's
#      ~/.ssh/authorized_keys, and tells the admin the address
#   4. the admin writes hosts/<name>/ — by running `kz create-host` ON the
#      target if the live image has nix, or by hand from the closest
#      existing host if it does not
#   5. the admin runs THIS, which installs NixOS over SSH with
#      nixos-anywhere + disko
#   6. the owner reboots, types the ZFS passphrase and logs in
#   7. the owner runs `kz configure` and `kz update` to add software
#
# Steps 1-3 are the owner's and are not automated: VPN credentials and key
# exchange are deliberately outside this toolset.
#
# WHAT --seed IS FOR
#
# The flake cannot be cloned into the owner's home during the install: the
# home does not exist until the machine has booted, and it cannot boot
# unattended because the ZFS passphrase is typed at a console. So the clone
# is a second, tiny step run once the machine is up.
#
# THIS DESTROYS THE TARGET'S DISK. disko partitions from scratch — that is
# what makes an unattended install possible, and it is unrecoverable. The
# confirmation names the machine, the address and the disk before anything
# happens.
set -uo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$REPO_ROOT" ] || {
  echo "install: not inside a git repository" >&2
  exit 1
}
cd "$REPO_ROOT" || exit 1

BOLD=$'\033[1m'
DIM=$'\033[2m'
RED=$'\033[38;2;200;70;60m'
GREEN=$'\033[38;2;88;150;50m'
YELLOW=$'\033[38;2;240;230;74m'
NC=$'\033[0m'

say() { printf '  %s\n' "$*"; }
ok() { printf '  %s✓%s %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$NC" "$*"; }
die() {
  printf '  %s✗%s %s\n' "$RED" "$NC" "$*" >&2
  exit 1
}

usage() {
  awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
}

HOST=""
TARGET=""
DRY_RUN=0
SEED=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run | -n) DRY_RUN=1 ;;
    --seed) SEED=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*) die "unknown option: $1" ;;
    *)
      if [ -z "$HOST" ]; then
        HOST="$1"
      elif [ -z "$TARGET" ]; then
        TARGET="$1"
      else
        die "too many arguments: $1"
      fi
      ;;
  esac
  shift
done

[ -n "$HOST" ] || {
  usage
  exit 1
}
[ -n "$TARGET" ] || die "name the machine to install onto, e.g. root@10.100.0.42"

[ -d "hosts/$HOST" ] || die "no hosts/$HOST/ — create the host profile first; see
    docs/developer/remote-install.md step 4"

# ── seed: clone the flake into the owner's home on the new machine ────────
if [ "$SEED" = 1 ]; then
  remote_user="${TARGET%@*}"
  [ "$remote_user" != "$TARGET" ] || die "--seed needs user@host, not just a host"
  [ "$remote_user" != root ] || warn "seeding as root; the owner will not own the checkout"

  origin=$(git remote get-url origin 2>/dev/null || true)
  [ -n "$origin" ] || die "this checkout has no 'origin' remote to clone from"

  printf '\n  %sSeeding the flake on %s%s\n' "$BOLD" "$TARGET" "$NC"
  say "  from: $origin"
  say "  into: ~/dev/nix-config, owned by $remote_user"
  say ""
  if [ "$DRY_RUN" = 1 ]; then
    ok "--dry-run: nothing was done."
    exit 0
  fi

  # Runs AS the owner, so everything it creates is already theirs. Idempotent:
  # a machine that already has the checkout is left alone rather than
  # clobbered, because the owner may have work in it.
  # The URL is passed as an ARGUMENT rather than interpolated into the
  # heredoc: a quoted heredoc cannot expand anything locally, which is what
  # keeps a surprising remote URL from becoming remote shell.
  ssh "$TARGET" bash -s -- "$origin" <<'EOF' || die "seeding failed"
set -euo pipefail
origin="$1"
mkdir -p ~/dev
if [ -d ~/dev/nix-config/.git ]; then
  echo "  ~/dev/nix-config already exists — leaving it alone"
else
  git clone "$origin" ~/dev/nix-config
  echo "  cloned into ~/dev/nix-config"
fi
EOF
  ok "seeded"
  say ""
  say "${DIM}Tell the owner: cd ~/dev/nix-config && nix develop, then kz configure${NC}"
  exit 0
fi

# ── install ───────────────────────────────────────────────────────────────

grep -q "disko.devices" "hosts/$HOST/disks.nix" 2>/dev/null \
  || die "hosts/$HOST/disks.nix is not a disko layout.
    nixos-anywhere partitions from scratch, so it needs one. A host adopted
    with \`kz create-host\` describes the filesystems it already had, which
    is deliberately NOT a layout that can repartition. Copy the shape from
    hosts/minimal/disks.nix and set the disk device."

disks=$(grep -oP 'device\s*=\s*"\K[^"]+' "hosts/$HOST/disks.nix" 2>/dev/null | sort -u | tr '\n' ' ')

printf '\n  %sInstall %s onto %s%s\n' "$BOLD" "$HOST" "$TARGET" "$NC"
printf '  %s%s%s\n' "$DIM" "$(printf '─%.0s' {1..66})" "$NC"
say ""
printf '  %s%sTHIS ERASES THE TARGET MACHINE.%s\n' "$RED" "$BOLD" "$NC"
say ""
say "disko will partition ${disks:-(no device found in disks.nix)} from scratch."
say "Everything on that disk goes, including any existing system."
say ""
say "${DIM}Check you are pointing at the right machine:${NC}"
say "${DIM}  ssh $TARGET 'lsblk; ip -brief addr'${NC}"
say ""

if [ "$DRY_RUN" = 1 ]; then
  say "${DIM}Would run:${NC}"
  say "  nix run .#nixos-anywhere -- --flake .#$HOST --target-host $TARGET"
  say ""
  ok "--dry-run: nothing was done."
  exit 0
fi

printf '  Type the hostname %s%s%s to confirm: ' "$BOLD" "$HOST" "$NC"
read -r confirm
[ "$confirm" = "$HOST" ] || die "not confirmed — nothing was done"

say ""
say "Checking the target answers..."
ssh -o BatchMode=yes -o ConnectTimeout=10 "$TARGET" true 2>/dev/null \
  || die "cannot reach $TARGET over SSH.
    The live system needs sshd running and your key in its authorized_keys.
    That is step 3, and it is the owner's to do."
ok "reachable"

say ""
say "Installing — this takes a while and streams a lot of output."
say ""
# The flake pins nixos-anywhere as an input; `nix run .#nixos-anywhere` is
# that exact version. Falling back to PATH would silently use whatever the
# machine happens to have, on the one command that repartitions a disk.
nix run .#nixos-anywhere -- \
  --flake ".#$HOST" \
  --target-host "$TARGET" \
  || die "nixos-anywhere failed"

say ""
ok "$HOST installed"
say ""
say "${BOLD}What the owner does next${NC}"
say "  1. reboot the machine and remove the live USB"
say "  2. type the ZFS passphrase at the prompt"
say "  3. log in"
say ""
say "${BOLD}Then, once it is up:${NC}"
say "  kz install $HOST <user>@$HOST --seed"
say "  ${DIM}clones this flake into their home so they can run kz configure${NC}"
say ""
