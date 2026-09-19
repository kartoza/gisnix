#!/usr/bin/env bash
# Read hardware facts off the RUNNING machine.
#
# Every function here answers one question about the system it is executing
# on, and prints the answer on stdout — nothing writes files, nothing prompts,
# nothing needs the repo. That makes them safe to call from anywhere and easy
# to check by eye: run one, look at the output.
#
# WHY PROBE AT ALL
#
# `gisnix create-host` migrates a machine someone installed themselves into this
# flake. The facts that make a host bootable — the ZFS hostId, which pool the
# root lives on, the ESP's UUID, whether the pool is encrypted — exist only on
# that machine. Getting one wrong does not produce a build error; it produces
# a system that builds cleanly and then fails to mount root at boot.
#
# So they are read, not asked for. The user confirms what was found rather
# than typing it from memory.
#
# A function that cannot determine its answer prints nothing and returns 1.
# Callers decide whether that is fatal — a missing GPU is fine, a missing
# hostId on a ZFS root is not.

# ── identity ──────────────────────────────────────────────────────────────

p_hostid() {
  # NixOS wants an 8-hex-digit hostId, and ZFS uses it to decide whether a
  # pool belongs to this machine. It MUST match what the pool was created
  # with or the import is refused at boot — which is why this is read rather
  # than generated. hosts/atoll/networking.nix carries the same warning.
  [ -r /etc/machine-id ] || return 1
  head -c 8 /etc/machine-id
}

p_hostname() { hostname 2>/dev/null || cat /etc/hostname 2>/dev/null; }

# ── processor and graphics ────────────────────────────────────────────────

p_cpu_vendor() {
  local v
  v=$(grep -m1 '^vendor_id' /proc/cpuinfo 2>/dev/null | awk '{print $3}')
  case "$v" in
    AuthenticAMD) echo amd ;;
    GenuineIntel) echo intel ;;
    *) return 1 ;;
  esac
}

p_cpu_model() {
  grep -m1 '^model name' /proc/cpuinfo 2>/dev/null \
    | cut -d: -f2- | sed 's/^ *//;s/  */ /g'
}

p_gpu_vendor() {
  # Reported as a space-separated list: a laptop with switchable graphics
  # genuinely has two, and both need their driver.
  command -v lspci >/dev/null 2>&1 || return 1
  local out=""
  local line
  while IFS= read -r line; do
    case "$line" in
      *[Nn][Vv][Ii][Dd][Ii][Aa]*) out="$out nvidia" ;;
      *[Aa][Mm][Dd]*|*[Rr][Aa][Dd][Ee][Oo][Nn]*|*[Aa][Tt][Ii]*) out="$out amd" ;;
      *[Ii][Nn][Tt][Ee][Ll]*) out="$out intel" ;;
    esac
  done < <(lspci 2>/dev/null | grep -Ei 'vga|3d controller|display controller')
  # shellcheck disable=SC2086
  set -- $out
  [ "$#" -gt 0 ] || return 1
  printf '%s\n' "$@" | sort -u | tr '\n' ' ' | sed 's/ $//'
}

p_gpu_model() {
  command -v lspci >/dev/null 2>&1 || return 1
  lspci 2>/dev/null | grep -Ei 'vga|3d controller' | head -1 | cut -d: -f3- | sed 's/^ *//'
}

# ── form factor ───────────────────────────────────────────────────────────

p_is_laptop() {
  # A battery is the honest test. It decides whether the host wants
  # services-system-power, and whether "workstation" means a desk or a bag.
  compgen -G '/sys/class/power_supply/BAT*' >/dev/null 2>&1
}

p_chassis() {
  local f=/sys/class/dmi/id/chassis_type
  [ -r "$f" ] || return 1
  case "$(cat "$f")" in
    3|4|6|7|13) echo desktop ;;
    8|9|10|11|14|31|32) echo laptop ;;
    17|23|28) echo server ;;
    *) return 1 ;;
  esac
}

p_vendor_model() {
  local v m
  v=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)
  m=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
  [ -n "$v$m" ] || return 1
  echo "$v $m" | sed 's/^ *//;s/ *$//;s/  */ /g'
}

# ── filesystems ───────────────────────────────────────────────────────────

p_fs_source() { findmnt -no SOURCE --target "$1" 2>/dev/null; }
p_fs_type()   { findmnt -no FSTYPE --target "$1" 2>/dev/null; }

p_fs_uuid() {
  # by-uuid is stable across kernel renumbering; /dev/nvme0n1p1 is not. A
  # generated config that names the raw device works until the day a second
  # NVMe is fitted and the numbering shifts.
  local dev="$1"
  [ -b "$dev" ] || return 1
  if command -v blkid >/dev/null 2>&1; then
    blkid -s UUID -o value "$dev" 2>/dev/null && return 0
  fi
  lsblk -no UUID "$dev" 2>/dev/null | head -1
}

p_esp() {
  # The EFI system partition, as mounted. Prefers /boot, falls back to the
  # conventional alternatives.
  local m
  for m in /boot /boot/efi /efi; do
    if findmnt -no TARGET "$m" >/dev/null 2>&1; then echo "$m"; return 0; fi
  done
  return 1
}

p_swap_devices() {
  # Prints one device path per line. Empty output means no swap, which is
  # normal here — software/base/zram.nix is the fleet's answer instead.
  command -v swapon >/dev/null 2>&1 || return 0
  swapon --show=NAME --noheadings 2>/dev/null || true
}

# ── ZFS ───────────────────────────────────────────────────────────────────

p_zfs_pools() {
  command -v zpool >/dev/null 2>&1 || return 1
  zpool list -H -o name 2>/dev/null
}

p_zfs_root_pool() {
  # The pool the root dataset lives on: "NIXROOT/root" -> "NIXROOT".
  local src
  src=$(p_fs_source /) || return 1
  [ "$(p_fs_type /)" = zfs ] || return 1
  echo "${src%%/*}"
}

p_zfs_encrypted() { # <pool>
  command -v zfs >/dev/null 2>&1 || return 1
  local e
  e=$(zfs get -H -o value encryption "$1" 2>/dev/null) || return 1
  [ -n "$e" ] && [ "$e" != off ]
}

p_zfs_encryption_roots() {
  # Datasets that hold their own key — these are what
  # boot.zfs.requestEncryptionCredentials must name. Asking for the wrong
  # one means an unbootable system that only reveals itself at the console.
  command -v zfs >/dev/null 2>&1 || return 1
  zfs get -H -o value encryptionroot -t filesystem 2>/dev/null \
    | grep -v '^-$' | sort -u
}

# ── the generated hardware configuration ──────────────────────────────────

p_hardware_config() {
  # nixos-generate-config's own view: kernel modules, CPU microcode hints,
  # and the platform string. --no-filesystems because this flake keeps
  # filesystem declarations in the host's disks.nix, where they can be read
  # and reviewed rather than buried in generated output.
  command -v nixos-generate-config >/dev/null 2>&1 || return 1
  nixos-generate-config --show-hardware-config --no-filesystems 2>/dev/null
}

p_hardware_body() {
  # Just the BODY of nixos-generate-config's module, so it can be spliced
  # into a file that adds attributes of its own. Its output is:
  #
  #     { config, lib, pkgs, modulesPath, ... }:
  #
  #     {
  #       imports = ...
  #     }
  #
  # so the body is everything between the first line that is a bare `{` and
  # the final `}`. Matching the FIRST line starting with `{` instead catches
  # the function header — which is how the first generated hardware.nix came
  # out with one brace unclosed.
  p_hardware_config | awk '
    BEGIN { started = 0; n = 0 }
    !started && /^[[:space:]]*\{[[:space:]]*$/ { started = 1; next }
    started { body[++n] = $0 }
    END {
      while (n > 0 && body[n] ~ /^[[:space:]]*$/) n--
      if (n > 0 && body[n] ~ /^[[:space:]]*\}[[:space:]]*$/) n--
      for (i = 1; i <= n; i++) print body[i]
    }'
}
