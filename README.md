# gisnix

A reproducible NixOS distribution for GIS workstations — ZFS-encryption-ready,
bundle-based software selection, and a Kartoza-branded installer you boot
from USB.

📖 **[Full documentation](https://kartoza.github.io/gisnix/)**

```bash
nix run --extra-experimental-features "nix-command flakes" github:kartoza/gisnix
```

## What this is

- **`kz` operator CLI** — one namespaced entry point (`kz configure`, `kz
  create-host`, `kz install`, `kz installer`, `kz bundles`, ...) driven from
  `utils/commands.json`, so a command is a flake app, a `kz` subcommand, and
  a dev-shell binary all from one script.
- **`kz installer`** — the self-driven, Kartoza-branded bootable-USB wizard
  (partition, create a host + user, install). `kz install` is the different,
  admin-driven path: nixos-anywhere over SSH into an already-booted live
  system. `kz installer --mock` fakes disks/network and the destructive
  steps, for fast iteration on the wizard itself.
- **Software bundles** — package sets under `software/`, each a
  `bundle.json` plus its NixOS modules. Turn them on/off with `kz configure`
  or by editing `hosts/<name>/config.nix` directly.
- **The QGIS bundle** — the current QGIS channels plus 23 pinned historical
  releases, GRASS, SAGA, CloudCompare, Google Earth Pro and friends.
- **Storage** — single-disk ZFS with AES-256-GCM passphrase encryption by
  default, or plain XFS, or multi-disk stripe/raidz/raidz2 — see
  `templates/disko/`.
- **`lib.mkHost`** — exposed so a downstream flake can build a host from
  gisnix's bundles/profiles/overlays while keeping only its own
  `hosts/<name>` and `users/<name>` in its own repo. Kartoza's internal
  fleet (`nix-config`) is built this way.

## Getting started

- `nix develop` — enter the dev shell (`kz` for the command list).
- `hosts/example/` — the installer's own test target: minimal base +
  minimal COSMIC, ZFS-encrypted single disk. Copy it as the starting point
  for your own host, or run `kz create-host <name>`.
- `nix run .#example-vm` — boot the example host in QEMU.
- `nix run .#test-install` — build the installer ISO and boot it in QEMU
  with a persistent test disk, for trying the real (non-mock) installer
  end-to-end without touching real hardware. VMware/VirtualBox: boot the
  built ISO the normal way — it's a standard UEFI installation image, no
  hypervisor-specific variant needed.

## License

MIT — see [LICENSE](LICENSE).

---

Made with 💗 by [Kartoza](https://kartoza.com) | [Donate!](https://github.com/sponsors/timlinux) | [GitHub](https://github.com/kartoza/gisnix)
