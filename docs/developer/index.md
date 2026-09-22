# Developer guide

For working on gisnix itself, or building your own fleet on top of it.

- **[Architecture](architecture.md)** — how a host is composed: `lib.mkHost`,
  the bundle registry, `hostPath`/`gisnixRoot`/`fleet` specialArgs, and why
  they exist.
- **[Adding a host](adding-a-host.md)** — the manual path (writing
  `hosts/<name>/` by hand) alongside the installer.
- **[The installer](installer.md)** — the Textual wizard's own structure,
  `--mock` mode, and why its software step installs a fixed bundle set
  instead of nesting `gisnix configure`'s picker.
- **[Building on gisnix](downstream-flakes.md)** — what `lib.mkHost` gives a
  downstream flake, and what's still rough around that edge.
- **[Releasing](releasing.md)** — version bump, changelog, tag, push — and
  what the tag push actually triggers.

## Development environment

```bash
nix develop        # gisnix for the command list
gisnix setup --mock   # or: python3 -m installer --mock, fastest loop
nix flake check
```

See [`gisnix` command reference](../references/commands.md) for everything the
dev shell gives you.
