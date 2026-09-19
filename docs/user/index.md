# User guide

This section is for people installing and running a gisnix machine day to
day — not developing gisnix itself (see the [developer guide](../developer/index.md)
for that).

- **[Quickstart](quickstart.md)** — download the ISO, boot it, run the
  installer.
- **[Keyboard remapping](keyboard.md)** — the home-row modifiers and
  navigation layer the `services-device-input-kanata` bundle gives you (on
  by default), and what to do about a second board.
- Once installed, `~/nixos-config` on your machine is your own tiny flake —
  it pins gisnix and holds only your host and user files. Change installed
  software by editing `hosts/<name>/config.nix`'s bundle list, then
  `sudo nixos-rebuild switch --flake .#<name>` (see the
  [quickstart](quickstart.md) for the full loop, and its note on the
  interactive `gisnix configure` menu).
