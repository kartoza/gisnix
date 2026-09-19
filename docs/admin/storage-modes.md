# Storage modes

The installer offers three storage modes, all built from the same disko
templates under `templates/disko/` (see
[Architecture](../developer/architecture.md) for how a host's `disks.nix`
picks one).

| Mode | Encryption | Disks | Notes |
|---|---|---|---|
| ZFS, single disk | AES-256-GCM, passphrase at boot | 1 | The installer's default |
| XFS, single disk | None | 1 | Maximum performance, dual-boot friendly |
| ZFS, multi-disk | Optional (on by default) | 2+ (stripe), 3+ (raidz), 4+ (raidz2) | Redundancy across disks |

## The ZFS dataset layout

Every ZFS mode (single or multi-disk) uses the same dataset shape:

```text
NIXROOT/
├── root      (/)           root filesystem
├── nix       (/nix)        nix store, quota-limited
├── home      (/home)       user data
├── overflow  (/overflow)   extra storage
└── atuin     (/var/atuin)  shell history, XFS zvol
```

This matches the layout real Kartoza fleet hosts use — a machine installed
by gisnix and one migrated by hand end up with the same shape.

## Changing your mind after install

**The storage mode itself isn't changeable after install** — `disks.nix`
describes how the disk was partitioned, not a knob `nixos-rebuild` can turn.
Changing it means reinstalling (the installer's "existing host profile"
option, pointed at your `hosts/<name>/`, does this cleanly — it's the same
config, freshly partitioned).

What *is* changeable without reinstalling: the software on top of the
storage (see [Software bundles](software-bundles.md)), and most ZFS dataset
options (quotas, compression) via a normal `hosts/<name>/disks.nix` edit
plus rebuild — those apply to an already-created pool. Repartitioning does
not.
