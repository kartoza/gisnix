# utils

Operator scripts for this flake — things you run by hand, as opposed to
modules the system builds. Docs generators live in `docs/scripts/`.

## The command list is not in this file

It used to be, and it rotted: this README described `rebuild.sh`,
`check.sh` and a machine-specific sync script long after they had been
renamed or folded into other commands.

Operator commands are declared once, in [`commands.json`](commands.json), and
minted from there into four surfaces:

| surface | how |
| --- | --- |
| `nix run .#<name>` | `flake.nix` builds a `writeShellApplication` per row |
| `./utils/<script>` | the implementation, also runnable directly |
| `gisnix` | `gisnix` alone prints the cheat-sheet; `gisnix <command>` runs one |
| `<leader>p<key>` | `.nvim.lua` reads the same manifest at startup |

So the current list is always:

```bash
gisnix                    # the cheat-sheet, from inside `nix develop`
```

A row whose script does not exist yet is skipped by the flake and shown
dimmed by `gisnix`. The manifest describes the intended lifecycle; the marker
tells you how much of it is built.

## Fleet metadata

Commands that act on a host — `update`, `check`, `suspend`, `wake`, `unlock`,
`inventory` — read [`../hosts/fleet.nix`](../hosts/fleet.nix) for its SSH user,
address, MAC, unlock port and deployment method. That registry is also what
generates `/etc/hosts` on every machine. Add a host there, not in a script.

## Shared libraries

`lib/` holds helpers inlined into commands by the manifest's `prelude` field.
They are inlined rather than sourced because `writeShellApplication` wraps a
single file, so a relative `source` would resolve against the store path of
the wrapper.

| library | used by |
| --- | --- |
| `lib/fleet.sh` | host lookup, reachability, SSH — `check`, `suspend`, `wake`, `unlock`, … |
| `lib/keycloak.sh` | token acquisition and the admin API — the `keycloak-*` commands |

## Scripts with no manifest row

These are not operator commands, so they are not in `commands.json`:

| script | purpose |
| --- | --- |
| `develop.nix` | the dev shell: packages, PATH and the entry banner |
| `dev-help.sh` | renders the cheat-sheet; invoked by `gisnix` and on shell entry |
| `nvidia-launch.sh` | launch an application on the NVIDIA GPU |
| `setup.sh` | the bootable-USB setup wizard (`gisnix setup [--mock]`) |
