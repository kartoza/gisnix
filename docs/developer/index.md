# Developer guide

For working on gisnix itself, or building your own fleet on top of it.

- **[Architecture](architecture.md)** — how a host is composed: `lib.mkHost`,
  the bundle registry, `hostPath`/`gisnixRoot`/`fleet` specialArgs, and why
  they exist.
- **[Adding a host](adding-a-host.md)** — the manual path (writing
  `hosts/<name>/` by hand) alongside the installer.
- **[The installer](installer.md)** — the Textual wizard's own structure,
  `--mock` mode, and how its software step reuses `kz configure`'s picker.
- **[Building on gisnix](downstream-flakes.md)** — what `lib.mkHost` gives a
  downstream flake, and what's still rough around that edge.

## Development environment

```bash
nix develop        # kz for the command list
kz installer --mock   # or: python3 -m installer --mock, fastest loop
nix flake check
```

See [`kz` command reference](../references/commands.md) for everything the
dev shell gives you.
