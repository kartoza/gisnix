---
hide:
  - navigation
  - toc
---

<div class="kz-hero" markdown>

<span class="kz-eyebrow">KARTOZA · GISNIX</span>

# A reproducible NixOS distribution for GIS workstations

Boot the installer, pick your software, get a ZFS-encrypted machine with a
minimal COSMIC desktop — or a full QGIS field workstation with 23 pinned
historical releases alongside it. One flake, declarative all the way down.

<div class="kz-cta" markdown>
[:material-rocket-launch: Quickstart](user/quickstart.md){ .kz-cta__primary }
[:material-server: Software bundles](references/bundles.md){ .kz-cta__secondary }
[:simple-github: GitHub](https://github.com/kartoza/gisnix){ .kz-cta__secondary }
</div>

</div>

## What it is

gisnix is a NixOS flake plus a Kartoza-branded, Textual-based installer you
boot from USB. It gives you:

- A **bundle registry** — package sets under `software/`, each a
  `bundle.json` plus its NixOS modules. Turn them on or off with `kz
  configure`, and implications resolve automatically (asking for the QGIS
  bundle brings in the desktop it needs to display it).
- **ZFS encryption by default** — AES-256-GCM, passphrase prompted at boot —
  or plain XFS, or multi-disk stripe/raidz/raidz2, all from one installer
  screen.
- The **`kz` operator CLI** — one namespaced entry point
  (`kz configure`, `kz installer`, `kz create-host`, `kz bundles`, ...)
  driven from a single manifest, so a command is a flake app, a `kz`
  subcommand, and a dev-shell binary all at once.
- **`lib.mkHost`**, exposed so your own flake can build a host from gisnix's
  bundles/profiles/overlays while keeping only your own `hosts/<name>` and
  `users/<name>` — see [Building on gisnix](developer/downstream-flakes.md).

## Who this is for

Field GIS teams who want a reproducible, encrypted workstation without
hand-tuning a distro from scratch, and anyone building their own NixOS fleet
on top of a maintained base rather than starting from an empty flake.

---

Made with 💗 by [Kartoza](https://kartoza.com) | [Donate!](https://github.com/sponsors/timlinux) | [GitHub](https://github.com/kartoza/gisnix)
