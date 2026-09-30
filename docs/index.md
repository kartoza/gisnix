---
hide:
  - navigation
  - toc
---

<div class="kz-hero" markdown>

<span class="kz-eyebrow">KARTOZA · GISNIX</span>

# GISNIX

An opinionated, open-source NixOS distribution for GIS workstations.
QGIS-centred, COSMIC on Wayland, ZFS-encrypted by default, keyboard-first,
and reproducible down to the ISO. Boot the installer, partition the disk,
pick your software from a bundle registry, and get a machine whose entire
configuration is one flake.

<div class="kz-cta" markdown>
[:material-download: Download Now!](https://github.com/kartoza/gisnix/releases/latest/download/gisnix-installer.iso){ .kz-cta__primary }
[:material-lightbulb-on: Why GISNIX](why.md){ .kz-cta__secondary }
[:material-book-open-variant: Quickstart](user/quickstart.md){ .kz-cta__secondary }
[:simple-github: Source](https://github.com/kartoza/gisnix){ .kz-cta__secondary }
</div>

</div>

!!! danger "Installing GISNIX erases the target disk"
    The installer **completely wipes the disk you install onto** — every
    existing partition and file is destroyed and **cannot be recovered**.
    Back up anything you need first, and be sure of the disk you choose.
    GISNIX and Kartoza accept **no responsibility for lost data**.

## Install on Your Machine

Most users want to grab the ISO and install GISNIX on real hardware.

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

A separate flake can pin GISNIX and build a host against its bundles and
profiles while keeping only its own host and user files — see
[Building on GISNIX](developer/downstream-flakes.md).

</div>

<div class="kz-feature" markdown>

### :material-arrow-u-left-top: Instant Rollbacks

Every rebuild is a new generation, selectable from the bootloader menu.
Whole-system, reproducible, and never a partial state.

</div>

<div class="kz-feature" markdown>

### :material-monitor: COSMIC on Wayland

One desktop, tracked close to upstream — System76's Rust compositor on
Wayland. Modern, GPU-accelerated, tiling-capable, and identical on every
GISNIX machine so muscle memory travels with you.

</div>

<div class="kz-feature" markdown>

### :material-keyboard: Keyboard-first, with speech

kanata is on by default — home-row mods, a nav layer, chords — no vendor
hardware needed. Hold right Ctrl and voxtype types what you say into
whatever field your cursor is in — on the CPU, no graphics card needed.

</div>

<div class="kz-feature" markdown>

### :material-shield-account: Sandboxed AI tools

Claude Code, Gemini CLI, OpenCode and a local Ollama workspace each run in
a bubblewrap jail, so a compromised assistant cannot reach your SSH agent,
your keys, or the rest of your home.

</div>

</div>

[What makes GISNIX opinionated :material-arrow-right:](why.md){ .md-button .md-button--primary }

---

## Requirements

UEFI boot, Secure Boot off, 48GB of disk at minimum (more if you're
taking several QGIS versions at once). The installer sizes every ZFS
dataset's quota from the disk you actually pick, always leaving 20GB
unclaimed as pool headroom — a disk too small for that gets rejected on
the storage screen instead of failing partway through the install. See
the [quickstart](user/quickstart.md) for the rest.

---

## AI statement

<div class="kz-author-note" markdown>

![Tim Sutton](assets/brand/timlinux-avatar.jpg){ .no-lightbox }

**Note from the Author:** This web site was substantially generated using
AI and reviewed by me, a human. Also many parts of the GISNIX project were
created, improved and supported using Claude. If you are looking for an
'AI Free' project, this is not the place for you. However this project is
also around 3 years of hard, manual work on my part — learning NixOS,
reviewing tools, desktop environments, wrangling .nix files by hand,
refactoring, streamlining and trying to figure out how to provide a great
user experience while trying to balance a tightrope of ethics, good and
useful technology etc. We do welcome contributions, including AI generated
improvements, but you need to thoroughly check and test your work first
which can be time consuming and is not something that can be delegated to
an AI agent.<br>
— *Tim Sutton ([@timlinux](https://github.com/timlinux))*

</div>

## Commercial support

<div class="kz-block" markdown>

![Kartoza](assets/brand/kartoza-logo-horizontal-color.png#only-light){ .no-lightbox .kz-block__logo }
![Kartoza](assets/brand/kartoza-logo-horizontal-reversed.png#only-dark){ .no-lightbox .kz-block__logo }

GISNIX is built and maintained by [Kartoza](https://kartoza.com), an
open-source geospatial company. If you are rolling GISNIX out across an
organisation and want help — deployment, custom enhancements, private
software bundles, training, or a support contract — Kartoza offers all
of these commercially.

[Get in touch :material-arrow-right:](https://kartoza.com/contact-us/){ .md-button .md-button--primary }

</div>

## Acknowledgements

GISNIX stands on the work of the NixOS, COSMIC, and QGIS communities.

<div class="kz-author-note" markdown>

![Tim Sutton](assets/brand/timlinux-avatar.jpg){ .no-lightbox }

**Tim Sutton** ([@timlinux](https://github.com/timlinux)) — author and
maintainer of GISNIX, co-founded Kartoza in 2014. My goal is to make
geospatial decision making tools available to everyone, and I hope GISNIX
helps you in your quest to use GIS.

</div>

---

Made with 💗 by [Kartoza](https://kartoza.com) | [Donate!](https://github.com/sponsors/timlinux) | [GitHub](https://github.com/kartoza/gisnix)
