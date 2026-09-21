# Changelog

All notable changes to gisnix are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.4.0] - 2026-09-20

Split Kartoza-internal apps from generically-useful ones — prompted by a
real nix-config migration hitting `pkgs.kartoza-timesheet` missing, and a
direct call on how the split should actually work.

### Added

- `desktop-kartoza-apps` now carries `kartoza-webapps` (23 of the
  original 25 web-app shortcuts — Gmail, Calendar, Meet, LinkedIn,
  ChatGPT, the Kartoza Handbook/Training/GeoCommunity public sites,
  and others — none of them Kartoza-internal) and `baboon.nix`
  (terminal typing-practice game; the package already existed in the
  overlay but nothing installed it, in either repo, until now).
- New opt-in sibling bundle `desktop-kartoza-apps-screencaster`
  (`kartoza-screencaster`, new flake input + overlay entry) —
  experimental (a known upstream build issue), so opt-in rather than
  part of the always-on set.

### Changed

- `desktop-kartoza-apps`'s description no longer says "none of this
  belongs in gisnix" — most of it always did; only two of the original
  25 web apps (an internal ERP, a private Sentry instance) and
  timesheets were ever actually Kartoza-internal, and those never
  moved here.

## [0.3.0] - 2026-09-20

First real downstream fleet migration, in progress — two nix-config hosts
now build through gisnix's own `mkHost`/`mkFleet`.

### Added

- `docs-generate-hosts` (per-host reference pages) now works the same way
  `configure`/`bundles` already did — reads gisnix's published bundle
  metadata, but runs its `nix eval` and writes generated pages against
  the calling flake's own root, not gisnix's checkout.
- `docs/user/fleet.md` — the fresh-install-to-fleet workflow: living with
  one host, turning it into a real repo, adding a second machine,
  `mkFleet`, and the `extraModules` pattern for private content gisnix's
  generic modules can't carry.

### Fixed

- `docs/developer/downstream-flakes.md` described the exact
  `GISNIX_ROOT`/`TARGET_ROOT` gap fixed in 0.2.0 as still open. Rewritten
  with `mkFleet`, the `projectConfig`/`fleet` override, `gisnixRoot`
  usage, and the CA-certificate re-attachment pattern — confirmed
  against a real migration, not just described.

## [0.2.0] - 2026-09-20

Groundwork for consuming gisnix from a real downstream fleet (nix-config),
prompted by starting that migration.

### Added

- `gisnix.lib.mkFleet`: scans a `hostsDir` for subdirectories carrying a
  `config.nix` and builds `nixosConfigurations` for all of them, with a
  shared or per-host `projectConfig`/`fleet`/`extraModules` override.
- `mkHost` and `mkFleet` accept `projectConfig`/`fleet` overrides, both
  defaulting to gisnix's own. Confirmed the hard way while planning
  nix-config's migration: gisnix's `nixosStateVersion` is `"26.05"`,
  nix-config's is `"25.05"`, and gisnix's `config.nix` is missing fields
  nix-config's own modules read directly — using `mkHost` unmodified on a
  real nix-config host would have silently changed values or hard-failed
  on a missing attribute.

### Fixed

- `configure`/`bundles` hard-refused to run outside a gisnix checkout, and
  `configure.sh` shelled out to a bare relative `utils/configure.py` path
  that only ever resolved by accident. Split `GISNIX_ROOT` (bundle
  catalogue, always gisnix's own tree) from `TARGET_ROOT` (a host's own
  files, always the caller's cwd) throughout the Python side; both
  commands now work from any consumer's own directory. Verified against a
  scratch directory with no gisnix checkout in it at all.

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
