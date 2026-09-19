#!/usr/bin/env bash
# Migrate a self-installed NixOS machine into this flake.
#
#   gisnix create-host foobar
#
# Reads the hardware facts off the machine it is running on, writes
# hosts/foobar/, registers it in hosts/fleet.nix, and stages the lot so
# `gisnix update foobar` can build it. The generated host starts minimal — a
# COSMIC desktop and a browser — with every other bundle present as a
# commented line to be enabled one at a time.
#
# THE WORKFLOW THIS SERVES
#
#   1. install NixOS yourself, with ZFS and encryption
#   2. nix-shell -p git
#   3. clone this flake
#   4. gisnix create-host foobar          <- you are here
#   5. gisnix update foobar
#   6. reboot into the new system
#   7. uncomment bundles as you need them, gisnix update again
#   8. open a PR with hosts/foobar/
#
# WHY IT PROBES INSTEAD OF ASKING
#
# The facts that decide whether a machine boots — the ZFS hostId, which pool
# root lives on, the ESP's UUID, which datasets hold keys — exist only on the
# machine itself. Getting one wrong does not fail the build. It produces a
# system that builds cleanly and then cannot mount root, discovered at a
# console with no shell. So they are read and shown for confirmation, never
# typed from memory.
#
# That is also why this refuses to run anywhere it cannot see the real
# system: in a container, a chroot or a build sandbox the readings are of the
# sandbox, and they look perfectly plausible.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$REPO_ROOT" ] || { echo "create-host: not inside a git repository." >&2; exit 1; }
cd "$REPO_ROOT"

# shellcheck source=lib/probe.sh disable=SC1091
. "$REPO_ROOT/utils/lib/probe.sh"

DRY_RUN=0
ASSUME_YES=0
NAME=""

# ── presentation ──────────────────────────────────────────────────────────
# gum when we have it, plain text when we do not. This runs on a machine that
# has just been installed, where the dev shell may not be entered yet.
#
# Every gum call ends its flags with `--`. Without it a message that begins
# with a dash is parsed as a flag: `say "--dry-run: ..."` aborted an entire
# dry run with "gum: error: unknown flag --dry-run".

has_gum() { command -v gum >/dev/null 2>&1; }

say()  { if has_gum; then gum style --foreground 4 -- "$*"; else printf '  %s\n' "$*"; fi; }
ok()   { if has_gum; then gum style --foreground 2 -- "  ✓ $*"; else printf '  ✓ %s\n' "$*"; fi; }
warn() { if has_gum; then gum style --foreground 3 -- "  ! $*"; else printf '  ! %s\n' "$*"; fi; }
die()  { if has_gum; then gum style --foreground 1 -- "  ✗ $*"; else printf '  ✗ %s\n' "$*" >&2; fi; exit 1; }

heading() {
  if has_gum; then
    gum style --border rounded --border-foreground 4 --padding "0 2" --margin "1 0" -- "$*"
  else
    printf '\n── %s ──\n' "$*"
  fi
}

ask() { # <prompt> <default>
  if [ "$ASSUME_YES" = 1 ]; then echo "$2"; return; fi
  if has_gum; then gum input --prompt "$1 " --value "$2" --
  else read -r -p "$1 [$2] " a; echo "${a:-$2}"; fi
}

choose() { # <prompt> <options…>
  local prompt="$1"; shift
  if [ "$ASSUME_YES" = 1 ]; then echo "$1"; return; fi
  if has_gum; then gum choose --header "$prompt" -- "$@"
  else
    printf '%s\n' "$prompt" >&2
    select o in "$@"; do [ -n "$o" ] && { echo "$o"; return; }; done
  fi
}

confirm() { # <prompt>
  if [ "$ASSUME_YES" = 1 ]; then return 0; fi
  if has_gum; then gum confirm -- "$1"
  else read -r -p "$1 [y/N] " a; [ "$a" = y ] || [ "$a" = Y ]; fi
}

usage() {
  cat <<EOF
Usage: gisnix create-host <name> [--dry-run]

  <name>      hostname for the new machine: lowercase letters, digits and
              hyphens, starting with a letter
  --dry-run   probe and show what would be written, touch nothing
  --yes, -y   take the default answer to every prompt instead of asking.
              For testing and for output that is being redirected to a file:
              a gum prompt written to a file blocks forever and looks hung.

Run this ON the machine being migrated.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) [ -z "$NAME" ] || die "only one host name, got '$NAME' and '$1'"; NAME="$1" ;;
  esac
  shift
done

# ── validation ────────────────────────────────────────────────────────────

[ -n "$NAME" ] || { usage; exit 1; }

case "$NAME" in
  [a-z]*[!a-z0-9-]*|[!a-z]*)
    die "'$NAME' is not a valid host name: lowercase letters, digits and hyphens, starting with a letter" ;;
esac

[ -d "hosts/$NAME" ] && die "hosts/$NAME already exists. Pick another name, or remove it first."
grep -q "^    $NAME = {" hosts/fleet.nix 2>/dev/null \
  && die "'$NAME' is already in hosts/fleet.nix but has no directory. Fix the registry first."

# ── the sandbox guard ─────────────────────────────────────────────────────
#
# In a container, chroot or nix build sandbox every probe still answers — it
# just answers about the sandbox. Root comes back as tmpfs, /etc/machine-id
# is absent, there are no pools. A host config written from that would build
# without complaint and then fail to mount root on the real machine.
#
# So the readings that cannot be plausibly wrong are checked first, and
# anything suspicious stops the run.

not_the_real_system() {
  local why=""
  [ "$(p_fs_type / 2>/dev/null)" = tmpfs ] && why="root filesystem is tmpfs"
  [ -r /etc/machine-id ] || why="${why:-/etc/machine-id is not readable}"
  if [ -r /proc/1/cgroup ] && grep -qE '(docker|lxc|containerd)' /proc/1/cgroup 2>/dev/null; then
    why="${why:-this looks like a container}"
  fi
  [ -n "${IN_NIX_SHELL:-}" ] && [ ! -e /etc/NIXOS ] && why="${why:-no /etc/NIXOS}"
  [ -n "$why" ] && { echo "$why"; return 0; }
  return 1
}

if reason=$(not_the_real_system); then
  die "$(cat <<EOF
this does not look like the machine being migrated ($reason).

create-host reads the hardware facts off the RUNNING system. Inside a
sandbox, container or chroot those readings describe the sandbox, and a host
config built from them will compile cleanly and then fail to mount root.

Run it on the target machine, outside any sandbox.
EOF
)"
fi

heading "Migrating this machine into the flake as '$NAME'"

confirm "Is this the machine that will run as '$NAME'?" \
  || die "Nothing written. Run create-host on the target machine."

# ── probe ─────────────────────────────────────────────────────────────────

heading "Reading this machine"

HOST_ID=$(p_hostid) || die "cannot read a hostId from /etc/machine-id — ZFS needs it to import the pool"
ROOT_SRC=$(p_fs_source /) || die "cannot determine the root filesystem"
ROOT_FS=$(p_fs_type /)    || die "cannot determine the root filesystem type"
CPU_VENDOR=$(p_cpu_vendor || echo "")
CPU_MODEL=$(p_cpu_model || echo "unknown")
GPU_VENDOR=$(p_gpu_vendor || echo "")
GPU_MODEL=$(p_gpu_model || echo "unknown")
MACHINE=$(p_vendor_model || echo "unknown")
ESP_MOUNT=$(p_esp || echo "")
ESP_DEV=""; ESP_UUID=""; ESP_FS=""
if [ -n "$ESP_MOUNT" ]; then
  ESP_DEV=$(p_fs_source "$ESP_MOUNT" || echo "")
  ESP_FS=$(p_fs_type "$ESP_MOUNT" || echo "vfat")
  [ -n "$ESP_DEV" ] && ESP_UUID=$(p_fs_uuid "$ESP_DEV" || echo "")
fi
ZFS_POOL=$(p_zfs_root_pool 2>/dev/null || echo "")
ENC_ROOTS=$(p_zfs_encryption_roots 2>/dev/null || true)
IS_LAPTOP=no; p_is_laptop && IS_LAPTOP=yes
# Passed as an array so the not-a-laptop case expands to nothing at all.
LAPTOP_FLAG=(); [ "$IS_LAPTOP" = yes ] && LAPTOP_FLAG=(--laptop)

printf '  %-14s %s\n' \
  "machine"   "$MACHINE" \
  "hostId"    "$HOST_ID" \
  "CPU"       "$CPU_MODEL${CPU_VENDOR:+  → ${CPU_VENDOR}}" \
  "GPU"       "$GPU_MODEL${GPU_VENDOR:+  → ${GPU_VENDOR}}" \
  "root"      "$ROOT_FS  $ROOT_SRC" \
  "laptop"    "$IS_LAPTOP"
[ -n "$ESP_MOUNT" ] && printf '  %-14s %s\n' "ESP" "$ESP_MOUNT  $ESP_DEV  ${ESP_UUID:-NO UUID}"
[ -n "$ZFS_POOL" ] && printf '  %-14s %s\n' "ZFS pool" "$ZFS_POOL"
[ -n "$ENC_ROOTS" ] && printf '  %-14s %s\n' "encrypted" "$(echo "$ENC_ROOTS" | tr '\n' ' ')"
echo

# Things that are survivable but worth saying out loud.
[ "$ROOT_FS" = zfs ] || warn "root is $ROOT_FS, not ZFS. The generated disks.nix will describe it, but this flake's tooling (snapshots, backups) assumes ZFS."
[ -n "$ESP_MOUNT" ] || warn "no EFI system partition found — this looks like a BIOS install. Check the generated disks.nix by hand."
[ -n "$ESP_UUID" ] || [ -z "$ESP_MOUNT" ] || warn "the ESP has no UUID; disks.nix will name the device directly, which breaks if disks are renumbered."
[ -n "$ENC_ROOTS" ] || warn "no encrypted ZFS datasets found. This fleet assumes encryption at rest — see software/base/zfs.nix."

confirm "Do those readings look right?" || die "Nothing written. Fix the system, or file the discrepancy."

# ── ask for what cannot be read ───────────────────────────────────────────

heading "About this host"

DESCRIPTION=$(ask "One-line description:" "${MACHINE} belonging to ${USER}")
OWNER=$(ask "Who uses it day to day:" "$USER")
SSH_USER=$(ask "Account the operator commands SSH as:" "$USER")

if [ "$IS_LAPTOP" = yes ]; then ROLE_DEFAULT=workstation; else ROLE_DEFAULT=workstation; fi
ROLE=$(choose "Role — how this machine is used:" workstation server test)
: "${ROLE:=$ROLE_DEFAULT}"

mapfile -t LOCALES < <(find software/locale -name 'locale-*.nix' -printf '%f\n' \
  | sed 's/^locale-//;s/\.nix$//' | sort)
LOCALE=$(choose "Locale and timezone:" "${LOCALES[@]}")
[ -n "$LOCALE" ] || die "a locale is required — a machine has one"

LAN_ADDRESS=$(ask "LAN address, or 'none' if it roams:" "none")
[ "$LAN_ADDRESS" = none ] && LAN_ADDRESS=""

# ── generate ──────────────────────────────────────────────────────────────

nix_str() { if [ -n "$1" ]; then printf '"%s"' "$1"; else printf 'null'; fi; }

gen_hardware() {
  # nixos-generate-config already emits the microcode line for the detected
  # CPU. Adding our own unconditionally produced the attribute twice, which
  # is an evaluation error, not a merge — so only add it if it is absent.
  local body
  body=$(p_hardware_body 2>/dev/null || true)
  [ -n "$body" ] || body="  # nixos-generate-config was unavailable; fill this in by hand."

  local extra=""
  if ! printf '%s' "$body" | grep -q 'updateMicrocode'; then
    case "$CPU_VENDOR" in
      amd)   extra="  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;" ;;
      intel) extra="  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;" ;;
    esac
  fi

  cat <<EOF
# Hardware for ${NAME} — GENERATED by \`gisnix create-host\` on $(date -u +%Y-%m-%d).
#
# The body below is nixos-generate-config's own view of this machine: kernel
# modules for the disk controllers, the platform string, and microcode.
# Filesystems are NOT here — they live in ./disks.nix, where they can be read
# and reviewed rather than buried in generated output.
#
# Detected: ${MACHINE}
#           ${CPU_MODEL}
#           ${GPU_MODEL}
#
# Re-run \`gisnix generate-hardware\` after a hardware change.

{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
${body}

  # The ZFS hostId. This MUST match the id the pool was created with, or ZFS
  # refuses to import it at boot and the machine drops to an initrd prompt.
  # Read from /etc/machine-id at creation time; verify with \`hostid\`.
  networking.hostId = "${HOST_ID}";
EOF
  [ -n "$extra" ] && printf '\n%s\n' "$extra"
  if [ "$IS_LAPTOP" = yes ]; then
    printf '\n  # A battery was detected, so this is treated as a laptop.\n'
    printf '  services.logind.lidSwitch = lib.mkDefault "suspend";\n'
  fi
  printf '}\n'
}

gen_disks() {
  cat <<EOF
# Filesystems for ${NAME} — GENERATED by \`gisnix create-host\` on $(date -u +%Y-%m-%d).
#
# This describes the disks as they ALREADY ARE. It is deliberately NOT a
# disko layout: nothing here can repartition or erase the machine, because
# this host was installed by hand and its data predates the flake.
#
# hosts/example/disks.nix takes the same approach for the same reason. A disko
# layout is a FORMATTING instruction; adding one to a machine with data on it
# is how a rebuild becomes a wipe.

{ lib, ... }:
{
  fileSystems."/" = {
    device = "${ROOT_SRC}";
    fsType = "${ROOT_FS}";
  };
EOF
  if [ -n "$ESP_MOUNT" ]; then
    if [ -n "$ESP_UUID" ]; then
      cat <<EOF

  # by-uuid rather than the raw device: /dev/nvme0n1p1 stops being correct
  # the day a second drive is fitted and the numbering shifts.
  fileSystems."${ESP_MOUNT}" = {
    device = "/dev/disk/by-uuid/${ESP_UUID}";
    fsType = "${ESP_FS:-vfat}";
  };
EOF
    else
      cat <<EOF

  # NOTE: no UUID could be read for this partition, so it is named directly.
  # That breaks if the disks are ever renumbered — replace with by-uuid.
  fileSystems."${ESP_MOUNT}" = {
    device = "${ESP_DEV}";
    fsType = "${ESP_FS:-vfat}";
  };
EOF
    fi
  fi
  if [ -n "$ENC_ROOTS" ]; then
    cat <<EOF

  # Datasets holding their own encryption key. The shared module in
  # software/base/zfs.nix asks for every pool; this narrows it to what this
  # machine actually has, so boot does not stall waiting for a passphrase
  # nobody has.
  boot.zfs.requestEncryptionCredentials = lib.mkForce [
EOF
    echo "$ENC_ROOTS" | sed 's/^/    "/;s/$/"/'
    echo "  ];"
  fi
  echo "}"
}

gen_networking() {
  cat <<EOF
# Networking for ${NAME} — GENERATED by \`gisnix create-host\`.

{ lib, projectConfig, hostname, ... }:
{
  networking = {
    useDHCP = lib.mkDefault true;
    networkmanager.enable = true;

    firewall = {
      # SSH only, and see software/services/system/ssh-access.nix if you want
      # it limited to the local network and the VPN rather than open.
      allowedTCPPorts = lib.mkForce [
        22 # SSH
      ];
      allowedUDPPorts = lib.mkForce [ ];
    };
  };

  networking.hostName = hostname;
  networking.domain = projectConfig.domain;
  # /etc/hosts for the fleet and its peers is generated from hosts/fleet.nix
  # — see software/services/system/fleet-hosts.nix. Only entries specific to
  # this host belong here.
}
EOF
}

gen_services() {
  cat <<EOF
# Host-specific services for ${NAME}.
#
# profiles/services.nix imports this for every host, so the file must exist
# even when it has nothing to say. Add anything only this machine runs.

{ ... }:
{
}
EOF
}

gen_default() {
  cat <<EOF
# ${NAME} — ${DESCRIPTION}
#
# Created by \`gisnix create-host\` from a self-installed NixOS system.
#
# The software this host installs is chosen in ./config.nix, which lists
# every bundle with most of them commented out. Enable them one at a time and
# rebuild between each — see the notes at the top of that file.

{
  inputs,
  outputs,
  config,
  pkgs,
  lib,
  projectConfig,
  hostname,
  hostConfig,
  ...
}:
{
  imports = [
    # Hardware, as read off this machine at creation time.
    ./hardware.nix
    ./disks.nix
    ./networking.nix

    # Users. Add yourself here — see users/ for the existing definitions,
    # and copy one as a starting point.
    ../../users/default.nix

    # System configuration.
    ../../profiles/common.nix
    ../../profiles/cosmic-desktop.nix
    ../../profiles/kartoza.nix
    ../../profiles/stylix.nix
    ../../profiles/services.nix
  ];

  system.stateVersion = projectConfig.nixosStateVersion;
}
EOF
}

# ── write ─────────────────────────────────────────────────────────────────

heading "Writing hosts/$NAME"

if [ "$DRY_RUN" = 1 ]; then
  say "dry run: showing what would be written, changing nothing."

  # Every generated file is also PARSED, in a temporary directory. Printing
  # nix that looks plausible is not evidence that it is valid: the first
  # version of gen_hardware emitted an unclosed brace and a duplicated
  # attribute, and read perfectly well by eye.
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  failed=0

  for f in hardware disks networking services default; do
    printf '\n───────── hosts/%s/%s.nix ─────────\n' "$NAME" "$f"
    "gen_$f" | tee "$tmp/$f.nix"
  done
  printf '\n───────── hosts/%s/config.nix ─────────\n' "$NAME"
  python3 utils/gen-host-config.py "$NAME" --locale "$LOCALE" "${LAPTOP_FLAG[@]}" \
    | tee "$tmp/config.nix"

  heading "Checking the generated Nix parses"
  for f in hardware disks networking services default config; do
    if nix-instantiate --parse "$tmp/$f.nix" >/dev/null 2>&1; then
      ok "$f.nix"
    else
      failed=1
      warn "$f.nix does NOT parse:"
      nix-instantiate --parse "$tmp/$f.nix" 2>&1 | head -5 | sed 's/^/      /'
    fi
  done

  if [ "$failed" = 1 ]; then
    die "the generator produced invalid Nix — fix it before creating a real host"
  fi
  ok "all six files parse"
  exit 0
fi

mkdir -p "hosts/$NAME"
gen_hardware   > "hosts/$NAME/hardware.nix";   ok "hardware.nix"
gen_disks      > "hosts/$NAME/disks.nix";      ok "disks.nix"
gen_networking > "hosts/$NAME/networking.nix"; ok "networking.nix"
gen_services   > "hosts/$NAME/services.nix";   ok "services.nix"
gen_default    > "hosts/$NAME/default.nix";    ok "default.nix"

python3 utils/gen-host-config.py "$NAME" --locale "$LOCALE" "${LAPTOP_FLAG[@]}" \
  > "hosts/$NAME/config.nix"
ok "config.nix  (every bundle listed, most commented out)"

# ── register in the fleet ─────────────────────────────────────────────────
#
# hosts/fleet.nix is the single source of truth: flake.nix reads it to decide
# which nixosConfigurations exist, so a host that is not in here cannot be
# built even if its directory is perfect.

heading "Registering in hosts/fleet.nix"

python3 - "$NAME" "$DESCRIPTION" "$ROLE" "$OWNER" "$SSH_USER" "$LAN_ADDRESS" <<'PY'
import sys, pathlib
name, desc, role, owner, ssh_user, lan = sys.argv[1:7]
p = pathlib.Path("hosts/fleet.nix")
t = p.read_text()

def nix(v):
    return f'"{v}"' if v else "null"

entry = f'''    {name} = {{
      description = "{desc}";
      role = "{role}";
      owner = "{owner}";
      sshUser = "{ssh_user}";
      lanAddress = {nix(lan)};
      aliases = [ ];
      macAddress = null;
      initrdSshPort = null;
      deploy = "local";
    }};
'''

# Insert before the closing brace of the `hosts` attrset, which is the line
# immediately preceding the unmanaged-peers banner.
marker = "  # ── Unmanaged peers"
idx = t.index(marker)
close = t.rindex("  };\n", 0, idx)
t = t[:close] + entry + t[close:]
p.write_text(t)
print(f"  registered {name}")
PY
ok "hosts/fleet.nix"

# ── docs navigation ───────────────────────────────────────────────────────
#
# The host's page under docs/hosts/ is GENERATED from the registry, so it
# will exist as soon as the docs are rebuilt. The nav entry is not generated
# — mkdocs.yml lists its pages explicitly — so it is added here, otherwise
# the page gets built and then never linked from anywhere.

python3 utils/add-host-to-nav.py "$NAME"
ok "mkdocs.yml"

# ── stage ─────────────────────────────────────────────────────────────────
#
# Nix evaluates the flake from the GIT TREE, not the working directory. An
# unstaged hosts/<name>/ is invisible to `gisnix update` and the error it
# produces ("path does not exist") points at nothing obvious. So stage it
# here, as part of creating it.

git add "hosts/$NAME" hosts/fleet.nix mkdocs.yml
ok "staged for git — nix reads the git tree, so this is required, not tidiness"

# ── verify ────────────────────────────────────────────────────────────────

heading "Checking it evaluates"

if nix eval --raw ".#nixosConfigurations.${NAME}.config.system.build.toplevel.drvPath" >/dev/null 2>&1; then
  ok "hosts/$NAME evaluates"
else
  warn "hosts/$NAME does not evaluate yet. The output below usually names the cause:"
  nix eval --raw ".#nixosConfigurations.${NAME}.config.system.build.toplevel.drvPath" 2>&1 | tail -20 | sed 's/^/      /'
  warn "Fix that before running gisnix update."
fi

# ── what next ─────────────────────────────────────────────────────────────

heading "Next"

cat <<EOF
  1. Add yourself as a user
       hosts/$NAME/default.nix imports users/default.nix only. Copy one of
       the files in users/ and add it there, or you will have no account on
       the new system.

  2. Build and switch
       gisnix update $NAME

  3. Reboot into it, then add software a bundle at a time
       Uncomment ONE line in hosts/$NAME/config.nix, run gisnix update $NAME,
       and keep it if it behaves. One per rebuild means a failure names its
       own cause.

  4. Open a pull request with hosts/$NAME/ and the fleet.nix entry, so the
     machine is inventoried with the rest of the fleet.

  Optional: add an integration test as tests/test-$NAME.nix and list it in
  tests.nix, so \`nix flake check\` covers this host too.
EOF
