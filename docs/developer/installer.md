# The installer

A Textual wizard living at `installer/` (Python), wired as the `setup`
row in `utils/commands.json` — `gisnix setup`, `nix run .#setup`, and
the standalone `setup` binary on the ISO's PATH are the same code, same
as every other operator command (see
[the gisnix command pattern](#why-a-gisnix-command) below). The `installer/`
directory name predates the command's rename to `setup` and refers to what
the wizard IS, not what you type — renaming a Python package tree is a much
bigger diff than renaming a manifest row, and nothing forces the two to
match.

## Screens

`installer/app.py` pushes a sequence of `Screen`s (in `installer/screens/`)
onto a stack; the sequence branches once, at `host_mode`, between a
new-host path and an existing-host-profile path:

```text
welcome → network → host_mode ─┬─→ host_details → user → storage → bundles ─┐
                                └─→ existing_host ──────────→ user → storage ┴─→ confirm → installing → done
```

Each screen validates its own answers into `self.app.state`
(`installer/state.py`, one `InstallState` dataclass threaded through the
whole wizard) before advancing.

## Software selection

The `bundles` screen doesn't open a picker — it installs the fixed
`DEFAULT_BUNDLES` set (`base` + minimal COSMIC, `installer/state.py`) and
moves on. It used to suspend the wizard (`with self.app.suspend():`) and
call `configure_tui.choose(...)`, the same picker `gisnix configure` uses
on an installed machine, but that picker is itself a Textual `App`, and
`App.run()` calls `asyncio.run()` — which cannot nest inside the
installer's own already-running event loop. `suspend()` releases the
terminal for a subprocess; it doesn't exit the installer's asyncio loop,
so the inner `asyncio.run()` still fires into a loop that's already
running and crashes. The same picker is one `gisnix configure` away once
the machine is up — running standalone there, with no outer loop to
collide with.

## Writing the new machine's files

`installer/writer.py` renders `hosts/<name>/{config.nix,default.nix,
hardware.nix,disks.nix,desktop.nix,services.nix}`, `users/<name>.nix`, and
the tiny per-machine `flake.nix`. The bundle list in `config.nix` is
rendered with `utils/lib/hostconfig.py`'s `render_block` — the same
renderer `gisnix create-host` uses, so a host the installer creates and one
created by hand are byte-identical in shape.

## Running the install

`installer/installer_run.py` is a generator that yields progress lines as
it works, so the `installing` screen can stream them into a log widget
rather than blocking silently:

1. Write the host/user/flake files to a temp directory. The generated
   `flake.nix` carries *two* `nixosConfigurations` at this point: the plain
   `<hostname>` and an install-only `<hostname>-install` with
   `stableCosmic = true` (see [Stable COSMIC for the first
   install](#stable-cosmic-for-the-first-install) below).
2. Lock the generated flake's `gisnix` input to *this ISO's own local
   copy* (`--override-input gisnix path:$GISNIX_ROOT`) — the install needs
   no network, and installs the exact revision the ISO was built from.
3. `disko --mode destroy,format,mount --flake <tmpdir>#<hostname>-install`
   — through `--flake`, not a raw `disks.nix` path, because `disks.nix`
   needs `gisnixRoot` supplied via the full module evaluation.
4. `nixos-install --flake <tmpdir>#<hostname>-install`.
5. Re-lock the `gisnix` input back to `github:kartoza/gisnix` (best-effort
   — needs network, but the machine is already fully installed either way)
   so the copy that lands in the new owner's home tracks upstream normally.
6. Overwrite `flake.nix` with the plain (no `stableCosmic`) version —
   `render_flake_nix(state)` with no `install=True` — so the `-install`
   output never reaches the new owner's home.
7. Copy the flake into `/home/<user>/nixos-config` on the new machine.

### Stable COSMIC for the first install {#stable-cosmic-for-the-first-install}

Every gisnix host pulls COSMIC from `nixpkgs-unstable` (see
`overlays/default.nix`) — that's deliberate for a *running* system doing an
occasional `gisnix update`, but it meant the very first install, watched
over someone's shoulder from a live ISO, could end up compiling desktop
components with no cache hit. nixos-26.05 (stable) already carries
`cosmic-comp` 1.2.0, fully built on cache.nixos.org.

`lib.mkHost` takes an optional `stableCosmic` argument, threaded into
`overlays/default.nix`, which swaps COSMIC's package source from
`nixpkgs-unstable` to `prev` (the stable nixpkgs already underneath
everything else) when set. It defaults to `false` — every host built by
`nix run .#<host>-vm`, every real fleet machine, and `gisnix update` on an
already-installed one all still pull COSMIC from `nixpkgs-unstable`, same
as before this existed. Only the installer's own `-install` output sets
it, and only for the one `nixos-install` run that needs to finish fast.

First boot is on stable COSMIC 1.2.0, already built. The first `gisnix
update` from `~/nixos-config` afterward moves the machine to bleeding-edge
COSMIC (and whatever else `nixpkgs-unstable` carries), which may compile
something Hydra hasn't gotten to yet — same as any `gisnix update` always
could, on any host.

## `--mock` mode

`installer/repo.py`'s `MOCK` flag (set by `GISNIX_INSTALLER_MOCK=1`,
`--mock`, or `nix run .#setup -- --mock`) fakes disk listing and the
network check, and swaps the real install for
`installer_run.run_install_mock` — which still writes real host/user/flake
files to a temp dir (so you can inspect the actual generated Nix) but never
touches `/mnt`, disko, or `nixos-install`. Fastest loop for iterating on the
screens themselves: `nix develop` then `python3 -m installer --mock` runs
straight from the working tree, no derivation rebuild between edits
(`textual` is in the dev shell's python for exactly this).

## Why a `gisnix` command {#why-a-gisnix-command}

Every operator-facing tool in this repo goes through the `gisnix` dispatcher —
one manifest row, one wrapper script, three surfaces generated from it (see
[Architecture](architecture.md#the-gisnix-command-manifest)). The setup
wizard is built the same way rather than as a hand-rolled
`writeShellApplication` pair: `packages.gisnix-setup` (what the ISO installs)
is built from the *same* `commands.json` row via `mkCommandDrv`, so there's
exactly one definition of what the wizard needs, not two.
