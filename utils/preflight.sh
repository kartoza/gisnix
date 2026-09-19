#!/usr/bin/env bash
# shellcheck disable=SC2154  # palette/helpers come from the inlined prelude
#
# preflight — checks to run against a host BEFORE rebuilding it.
#
# Generalised from bay-preflight.sh, which was written for one in-place
# takeover and hardcoded that machine's expectations. The questions it asked
# are the right ones for any host, because they are the ones that turn a
# rebuild into a machine that builds fine and then does not boot:
#
#   * does the firmware mode match the bootloader the config declares?
#   * does the running ZFS hostId match the declared one?
#   * do the filesystems the config expects actually exist?
#   * is there room for the new closure?
#   * do the users the config declares still have their home directories?
#
# Each check prints PASS, WARN or FAIL. Do not rebuild while anything is FAIL.
#
#   gisnix preflight              # this machine
#   gisnix preflight bay          # over SSH
#
# The declared side comes from evaluating the host's configuration, so this is
# comparing the flake against reality rather than against assumptions.
set -uo pipefail

case "${1:-}" in
  -h | --help)
    awk 'NR>1 && /^# shellcheck/ {next} NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
    exit 0
    ;;
esac

f_require_repo
HOST="$(f_resolve_host "${1:-}")" || exit 1
SELF="$(hostname -s 2>/dev/null || true)"

NIX=(nix --extra-experimental-features 'nix-command flakes')

echo
echo "${f_bold}Preflight — ${HOST}${f_nc}"
echo "${f_dim}reading what the flake declares…${f_nc}"

decl() { # <nix attribute path under the host config> <default>
  "${NIX[@]}" eval --raw \
    ".#nixosConfigurations.${HOST}.config.$1" 2> /dev/null || printf '%s' "$2"
}

WANT_HOSTID="$(decl networking.hostId '')"
WANT_SYSTEMD_BOOT="$(
  "${NIX[@]}" eval ".#nixosConfigurations.${HOST}.config.boot.loader.systemd-boot.enable" 2> /dev/null || echo false
)"
WANT_GRUB_EFI="$(
  "${NIX[@]}" eval ".#nixosConfigurations.${HOST}.config.boot.loader.grub.efiSupport" 2> /dev/null || echo false
)"
# isNormalUser is the flag NixOS itself uses to distinguish a person from a
# service account. An earlier version filtered by name prefix, which reported
# cosmic-greeter, flatpak, pcscd, usbmux and seven others as missing their home
# directories — they are daemons and have none.
# shellcheck disable=SC2016  # a Nix expression; ${n} is Nix, not shell
WANT_USERS="$(
  "${NIX[@]}" eval --raw --apply \
    'us: builtins.concatStringsSep " " (
       builtins.filter (n: us.${n}.isNormalUser or false) (builtins.attrNames us)
     )' \
    ".#nixosConfigurations.${HOST}.config.users.users" 2> /dev/null
)"

# Whether the config declares a separate /boot, so its absence can be judged
# rather than assumed to be a problem.
WANT_BOOT_FS="$(
  "${NIX[@]}" eval ".#nixosConfigurations.${HOST}.config.fileSystems" \
    --apply 'fs: builtins.hasAttr "/boot" fs' 2> /dev/null || echo false
)"

# The checks run on the target. Piped through bash explicitly because the
# login shell on these hosts is fish.
CHECKS=$(
  cat << 'REMOTE'
fails=0; warns=0

# Is this a real booted machine, or a container/sandbox where the boot state
# simply is not visible? Without this gate the environment-dependent checks
# produce confident FAILs about firmware and /boot that say nothing about the
# host — which is exactly the kind of output that trains people to ignore it.
if [ -d /sys/firmware ]; then real_boot=1; else real_boot=0; fi
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$1"; warns=$((warns+1)); }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fails=$((fails+1)); }
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

if [ "$real_boot" -eq 0 ]; then
  printf '\033[33m  Note: /sys/firmware is absent, so this is a container or sandbox\n'
  printf '  rather than the running host. Boot-related checks below can only\n'
  printf '  report "cannot verify".\033[0m\n'
fi

section "1. Firmware mode vs declared bootloader"
# /sys/firmware missing entirely means we are not looking at real firmware —
# a container or a sandbox. Reporting that as BIOS produced a confident FAIL
# on a machine that is in fact booted UEFI.
if [ -d /sys/firmware/efi ]; then
  running_fw=UEFI
elif [ -d /sys/firmware ]; then
  running_fw=BIOS
else
  running_fw=UNKNOWN
fi
if [ "$running_fw" = "UNKNOWN" ]; then
  warn "cannot read firmware mode — this is not a real boot; run it on the host"
elif [ "$WANT_SYSTEMD_BOOT" = "true" ] || [ "$WANT_GRUB_EFI" = "true" ]; then
  if [ "$running_fw" = "UEFI" ]; then
    pass "booted UEFI, and the config declares an EFI bootloader"
  else
    fail "config declares an EFI bootloader but this machine booted in BIOS mode — it will build and then not boot"
  fi
else
  if [ "$running_fw" = "BIOS" ]; then
    pass "booted BIOS, and the config declares a BIOS bootloader"
  else
    warn "booted UEFI but the config declares no EFI support — check boot.loader"
  fi
fi

section "2. ZFS hostId"
if [ -z "$WANT_HOSTID" ]; then
  warn "config declares no networking.hostId (only matters if this host uses ZFS)"
elif [ ! -r /etc/hostid ]; then
  warn "no /etc/hostid here; config declares $WANT_HOSTID (expected if this is not the host itself)"
else
  running_id=$(hostid 2>/dev/null || echo "")
  if [ "$running_id" = "$WANT_HOSTID" ]; then
    pass "hostid $running_id matches the config"
  else
    fail "running hostid '$running_id' != declared '$WANT_HOSTID' — ZFS pools will not import on boot"
  fi
fi

section "3. Room for the new closure"
avail=$(df --output=avail -BG / 2>/dev/null | tail -1 | tr -dc '0-9')
if [ -z "$avail" ]; then
  warn "could not read free space on /"
elif [ "$avail" -ge 15 ]; then
  pass "${avail}G free on /"
elif [ "$avail" -ge 5 ]; then
  warn "only ${avail}G free on / — a desktop closure can want more; consider nix-collect-garbage"
else
  fail "only ${avail}G free on / — the rebuild will likely run out of space"
fi

section "4. Pools"
if command -v zpool >/dev/null 2>&1; then
  if ! zpool list -H >/dev/null 2>&1; then
    warn "cannot query zpool (usually means no permission) — re-run where you can read pools"
  elif [ -n "$(zpool list -H 2>/dev/null)" ]; then
    unhealthy=$(zpool list -H -o health 2>/dev/null | grep -vc '^ONLINE$' || true)
    if [ "${unhealthy:-0}" -eq 0 ]; then
      pass "all pools ONLINE"
    else
      fail "$unhealthy pool(s) not ONLINE — fix before rebuilding"
    fi
    zpool list -o name,size,alloc,health 2>/dev/null | sed 's/^/        /'
  else
    warn "zpool present but no pools imported"
  fi
else
  pass "no ZFS on this host"
fi

section "5. Users the config declares"
for u in $WANT_USERS; do
  if id "$u" >/dev/null 2>&1; then
    if [ -d "/home/$u" ]; then
      pass "$u exists, /home/$u present"
    else
      warn "$u exists but /home/$u is missing"
    fi
  else
    warn "$u is declared but does not exist yet (the rebuild will create it)"
  fi
done
[ -n "$WANT_USERS" ] || warn "could not determine the declared users"

section "6. Boot filesystem"
if [ "$WANT_BOOT_FS" != "true" ]; then
  pass "config declares no separate /boot"
elif [ "$real_boot" -eq 0 ]; then
  warn "cannot check /boot from here (not a real boot) — run this on the host"
elif mountpoint -q /boot 2>/dev/null; then
  bavail=$(df --output=avail -BM /boot 2>/dev/null | tail -1 | tr -dc '0-9')
  if [ "${bavail:-0}" -ge 100 ]; then
    pass "/boot mounted, ${bavail}M free"
  else
    fail "/boot has only ${bavail}M free — not enough for another generation"
  fi
else
  fail "config declares /boot but it is not mounted here"
fi

printf '\n\033[1mResult\033[0m\n'
if [ "$fails" -gt 0 ]; then
  printf '  \033[31m%s FAIL, %s WARN — do not rebuild yet\033[0m\n' "$fails" "$warns"
  exit 1
fi
if [ "$warns" -gt 0 ]; then
  printf '  \033[33m%s WARN — read them, then rebuild if you are happy\033[0m\n' "$warns"
  exit 0
fi
printf '  \033[32mall checks passed\033[0m\n'
REMOTE
)

# Values the target needs, passed as an environment prelude rather than
# interpolated into the body, so a value containing a quote cannot break it.
ENVPRE="WANT_BOOT_FS=$(printf '%q' "$WANT_BOOT_FS")
WANT_HOSTID=$(printf '%q' "$WANT_HOSTID")
WANT_SYSTEMD_BOOT=$(printf '%q' "$WANT_SYSTEMD_BOOT")
WANT_GRUB_EFI=$(printf '%q' "$WANT_GRUB_EFI")
WANT_USERS=$(printf '%q' "$WANT_USERS")
"

if [ "$HOST" = "$SELF" ]; then
  echo "${f_dim}running locally${f_nc}"
  printf '%s\n%s\n' "$ENVPRE" "$CHECKS" | bash
  exit $?
fi

f_require_deployable "$HOST"
f_require_reachable "$HOST"

echo "${f_dim}running over SSH as $(f_field "$HOST" sshUser "$USER")${f_nc}"
printf '%s\n%s\n' "$ENVPRE" "$CHECKS" | f_ssh "$HOST" bash -s
