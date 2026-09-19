# User guide

This section is for people installing and running a gisnix machine day to
day — not developing gisnix itself (see the [developer guide](../developer/index.md)
for that).

- **[Quickstart](quickstart.md)** — download the ISO, boot it, run the
  installer.
- Once installed, `~/nixos-config` on your machine is your own tiny flake —
  it pins gisnix and holds only your host and user files. Change installed
  software by editing `hosts/<name>/config.nix`'s bundle list, then
  `sudo nixos-rebuild switch --flake .#<name>` (see the
  [quickstart](quickstart.md) for the full loop, and its note on the
  interactive `kz configure` menu).
