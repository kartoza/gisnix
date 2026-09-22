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

## Install on Your Machine

Most users want to grab the ISO and install gisnix on real hardware.

<div class="kz-features" markdown>

<div class="kz-feature" markdown>

### :material-download: 1. Get the ISO

[Download the latest release](https://github.com/kartoza/gisnix/releases/latest)
or build it yourself:

```bash
git clone https://github.com/kartoza/gisnix
cd gisnix
nix build .#nixosConfigurations.installer.config.system.build.isoImage
```

</div>

<div class="kz-feature" markdown>

### :material-usb-flash-drive: 2. Flash & Boot

Write the ISO to a USB drive and boot from it — UEFI required, Secure
Boot off.

See [making a bootable USB stick](user/bootable-usb.md) for
balenaEtcher/`dd`/Rufus instructions, or try it first with `nix run
.#test-install` — no USB drive needed, boots straight into QEMU.

</div>

<div class="kz-feature" markdown>

### :material-wizard-hat: 3. Run Setup

The Kartoza-branded TUI installer walks you through account setup,
storage (ZFS single-disk encrypted, plain XFS, or multi-disk ZFS),
locale, boot theme, and a starting software selection.

```bash
sudo setup
```

</div>

</div>

[Full Quickstart Guide :material-arrow-right:](user/quickstart.md){ .md-button .md-button--primary }
[Making a Bootable USB Stick :material-arrow-right:](user/bootable-usb.md){ .md-button }

---

## What You Get

<div class="kz-features" markdown>

<div class="kz-feature" markdown>

### :material-view-grid: Bundles

Software organised into named sets under `software/`, each a
`bundle.json` describing what it needs. `gisnix configure` gives you a
menu instead of hand-editing `config.nix` — dependencies resolve on
their own, so asking for the QGIS bundle also gets you the desktop it
needs to run in.

</div>

<div class="kz-feature" markdown>

### :material-map: QGIS, Several Ways

The current release channels, plus 23 pinned historical QGIS releases
going back to 1.8, each installed from its own pinned nixpkgs so the
old and the current don't fight over shared library versions.

</div>

<div class="kz-feature" markdown>

### :material-shield-lock: Encrypted Storage

ZFS on a single disk with AES-256-GCM encryption is the installer's
default — a passphrase prompt at boot. Plain XFS and multi-disk ZFS
(stripe, RAIDZ, RAIDZ2) are the alternatives; see
[storage modes](admin/storage-modes.md).

</div>

<div class="kz-feature" markdown>

### :material-console-line: One Command

Every operational task — configuring software, creating a host, running
the installer itself — is `gisnix <command>`, driven from a single
manifest so a new one gets a flake app, a subcommand, and a dev-shell
binary from one entry.

</div>

<div class="kz-feature" markdown>

### :material-source-fork: `lib.mkHost`

A separate flake can pin gisnix and build a host against its bundles and
profiles while keeping only its own host and user files — see
[Building on gisnix](developer/downstream-flakes.md).

</div>

<div class="kz-feature" markdown>

### :material-arrow-u-left-top: Instant Rollbacks

Every rebuild is a new generation, selectable from the bootloader menu.
Whole-system, reproducible, and never a partial state.

</div>

</div>

---

## Requirements

UEFI boot, Secure Boot off, 20GB of disk at minimum (more if you're
taking several QGIS versions at once). See the
[quickstart](user/quickstart.md) for the rest.

---

Made with 💗 by [Kartoza](https://kartoza.com) | [Donate!](https://github.com/sponsors/timlinux) | [GitHub](https://github.com/kartoza/gisnix)
