---
hide:
  - navigation
  - toc
---

<div class="kz-hero" markdown>

<span class="kz-eyebrow">KARTOZA · GISNIX</span>

# gisnix

A NixOS distribution for GIS workstations. Boot the installer, partition
the disk, pick your software from a bundle registry, and get a machine
whose entire configuration is one flake — reproducible, and, if you chose
ZFS, encrypted with a passphrase prompted at boot.

<div class="kz-cta" markdown>
[:material-download: Download Now!](https://github.com/kartoza/gisnix/releases/latest/download/gisnix-installer.iso){ .kz-cta__primary }
[:material-book-open-variant: Quickstart](user/quickstart.md){ .kz-cta__secondary }
[:material-format-list-bulleted: Software bundles](references/bundles.md){ .kz-cta__secondary }
[:simple-github: Source](https://github.com/kartoza/gisnix){ .kz-cta__secondary }
</div>

</div>

## What it is

A NixOS flake, an installer, and a QGIS distribution, in that order of
what actually determines the other two:

- **Bundles.** Software is organised into named sets under `software/`,
  each one a `bundle.json` describing what it contains and what it
  requires. A host lists the bundles it wants in `config.nix`; `gisnix
  configure` gives you a menu instead of editing that list by hand.
  Dependencies resolve on their own — asking for the QGIS bundle also
  gets you the desktop it needs to run in.
- **QGIS, several ways.** The current release channels, plus 23 pinned
  historical QGIS releases going back to 1.8, each installed from its own
  pinned nixpkgs so the old and the current don't fight over shared
  library versions.
- **Storage.** ZFS on a single disk with AES-256-GCM encryption is the
  installer's default. Plain XFS and multi-disk ZFS (stripe, RAIDZ,
  RAIDZ2) are the alternatives — see [storage modes](admin/storage-modes.md).
- **`gisnix`, the command.** Every operational task — configuring
  software, creating a host, running the installer itself — is one
  command, driven from a manifest so a new one gets a flake app, a
  subcommand, and a dev-shell binary from a single entry.
- **`lib.mkHost`.** A separate flake can pin gisnix and build a host
  against its bundles and profiles while keeping only its own host and
  user files — see [Building on gisnix](developer/downstream-flakes.md).

## Requirements

UEFI boot, Secure Boot off, 20GB of disk at minimum (more if you're
taking several QGIS versions at once). See the
[quickstart](user/quickstart.md) for the rest.

---

Made with 💗 by [Kartoza](https://kartoza.com) | [Donate!](https://github.com/sponsors/timlinux) | [GitHub](https://github.com/kartoza/gisnix)
