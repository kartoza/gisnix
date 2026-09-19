# Architecture

## How a host is built

`flake.nix` exposes `lib.mkHost`:

```nix
mkHost = hostname: { hostPath ? ./hosts + "/${hostname}", extraModules ? [ ] }:
  nixpkgs.lib.nixosSystem { ... };
```

Every host — gisnix's own `example`, or one in a downstream flake — goes
through this one function. It wires in disko, agenix, home-manager, stylix,
the bundle-resolution module (`profiles/bundles.nix`), and the overlay set,
then imports `hostPath` (a directory containing at least `default.nix` and
`config.nix`).

## Three specialArgs that make a host portable

A host's own files sit in `hostPath`, wherever that is. But a host's
`default.nix` also needs to reach things that live in *gisnix*, not in its
own directory — shared profiles, the locale modules, the fleet registry.
Three `specialArgs` make that possible regardless of where `hostPath` is:

| specialArg | What it is | Used for |
|---|---|---|
| `hostPath` | The host's own directory | A profile that needs a per-host override file (e.g. `cosmic-desktop.nix` wanting `desktop.nix`) reaches it via `hostPath + "/desktop.nix"` rather than a `../hosts/${hostname}/...` path that would resolve against the wrong repo. |
| `gisnixRoot` | This flake's own root (`./.`), as an absolute path | A host's `default.nix` imports shared, non-bundle profiles with `gisnixRoot + "/profiles/cosmic-desktop.nix"` instead of `../../profiles/...`, which only works when the host happens to live inside gisnix's own tree. |
| `fleet` | The parsed `hosts/fleet.nix` | Bundle-driven modules like `fleet-hosts.nix` (generates `/etc/hosts` for every known machine) take the registry as an argument instead of importing a hardcoded path — a downstream flake has its own `fleet.nix`, not gisnix's. |

This is the fix that makes `hostPath` pointing *outside* gisnix's own repo
actually work — see [Building on gisnix](downstream-flakes.md).

## The bundle registry

Every bundle is a directory under `software/` with a `bundle.json`
(name, path, description, `implies`, `modules`) beside the NixOS modules it
describes. `profiles/bundles.nix` reads a host's `config.nix` `bundles`
list, resolves implications transitively, and turns the result into module
imports. Nothing here is fleet-specific — the whole registry, and the `kz`
tooling that reads it (`utils/lib/hostconfig.py`, `bundleinfo.py`,
`configure_tui.py`), is exactly the same code used by nix-config's own
fleet, one layer up.

## Storage templates

`templates/disko/*.nix` are plain functions — `{ device, ... }: { disko.devices = ...; }`
— not modules, so they can be called directly from a host's `disks.nix`:

```nix
{ gisnixRoot, ... }:
import (gisnixRoot + "/templates/disko/zfs-encrypted-single.nix") { device = "/dev/sda"; }
```

`disks.nix` itself has to be a module function (to receive `gisnixRoot`),
even though its body is just an `import` call — see
`hosts/example/disks.nix` for the exact shape.

## The `kz` command manifest

Every operator-facing tool is a row in `utils/commands.json` plus a
`utils/<name>.sh` wrapper. `mkCommandDrv` in `flake.nix` turns one row into
three surfaces: a `nix run .#<name>` app, a `kz <name>` subcommand (via
`kzDispatcher`), and a dev-shell binary — one script, one dependency list,
no duplication. See the [command reference](../references/commands.md) for
every command that exists today, and
[the kz command pattern](../developer/installer.md#why-a-kz-command) for
why the installer itself is wired this way rather than as a bespoke flake
app.
