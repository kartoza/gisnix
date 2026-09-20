# Changelog

All notable changes to gisnix are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-09-20

First tagged version. First confirmed end-to-end install in a VM: disk
partitioning, ZFS-encrypted root, bootloader, first boot, ZFS passphrase
unlock, and a working COSMIC desktop login — the milestone the rest of
this project builds on.

### Added

- Kartoza-branded Python/Textual installer, mock and live modes.
- GitHub-username SSH key import on the user-account step.
- Bundle registry (`software/`) with `gisnix configure`/`bundles`/`create-host`.
- `gisnix.lib.mkHost`, consumable from a downstream flake.
- Push-to-talk voice-to-text (voxtype) on hold-Menu, wired through kanata.
- `AGENTS.md` for both this repo and nix-config.

### Fixed

- Kanata config bugs that could block install builds outright.
- `install-grub.sh` hangs caused by `useOSProber` scanning the live ISO's
  own CD-ROM device.
- Default install bundle bloat (`desktop-base-extras`, `zfs-backup` pulled
  into every install regardless of bundle choice).
- Root account locked in emergency mode after `nixos-install --no-root-passwd`.
- Installed system's console font stuck at an unreadably small default.
- `boot.zfs.forceImportRoot = false` caused every install's first boot to
  fail importing its own freshly created pool (hostid mismatch between the
  live installer environment and the installed system).
- `~/.config` left owned by root after dotfile-deploying activation
  scripts, blocking COSMIC's first-run config creation.
