# Administration

Running a gisnix machine (or a small fleet of them) day to day.

- **[Software bundles](software-bundles.md)** — how the bundle system
  works, and the safe way to change what's installed.
- **[Storage modes](storage-modes.md)** — what the installer set up, and
  what's safe to change after the fact (mostly: nothing about the disk
  layout itself — see why).

## Fleet metadata

If you're managing more than one gisnix machine and want them to know about
each other (so `ssh othermachine` works by name, for instance), see
`hosts/fleet.nix` — see [Architecture](../developer/architecture.md) for
how it's read. A single standalone machine doesn't need this at all.

## Reinstalling

The installer's "existing host profile" option (see the
[quickstart](../user/quickstart.md)) reinstalls a machine from a
previously-committed `hosts/<name>/` directory rather than starting fresh —
useful for restoring a machine to a known-good configuration, or for
provisioning a second physical machine with the same profile.
