# The installer

A Textual wizard living at `installer/` (Python), wired as the `installer`
row in `utils/commands.json` — `kz installer`, `nix run .#installer`, and
the standalone `installer` binary on the ISO's PATH are the same code, same
as every other operator command (see
[the kz command pattern](#why-a-kz-command) below).

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

## Reusing `kz configure`'s picker

The `bundles` screen doesn't reimplement a software picker. It suspends the
wizard (`with self.app.suspend():`) and calls `configure_tui.choose(...)` —
the exact same function `kz configure` uses on an installed machine — then
resumes with whatever was selected. One picker, two contexts.

## Writing the new machine's files

`installer/writer.py` renders `hosts/<name>/{config.nix,default.nix,
hardware.nix,disks.nix,desktop.nix,services.nix}`, `users/<name>.nix`, and
the tiny per-machine `flake.nix`. The bundle list in `config.nix` is
rendered with `utils/lib/hostconfig.py`'s `render_block` — the same
renderer `kz create-host` uses, so a host the installer creates and one
created by hand are byte-identical in shape.

## Running the install

`installer/installer_run.py` is a generator that yields progress lines as
it works, so the `installing` screen can stream them into a log widget
rather than blocking silently:

1. Write the host/user/flake files to a temp directory.
2. Lock the generated flake's `gisnix` input to *this ISO's own local
   copy* (`--override-input gisnix path:$GISNIX_ROOT`) — the install needs
   no network, and installs the exact revision the ISO was built from.
3. `disko --mode destroy,format,mount --flake <tmpdir>#<hostname>` —
   through `--flake`, not a raw `disks.nix` path, because `disks.nix` needs
   `gisnixRoot` supplied via the full module evaluation.
4. `nixos-install --flake <tmpdir>#<hostname>`.
5. Re-lock the `gisnix` input back to `github:kartoza/gisnix` (best-effort
   — needs network, but the machine is already fully installed either way)
   so the copy that lands in the new owner's home tracks upstream normally.
6. Copy the flake into `/home/<user>/nixos-config` on the new machine.

## `--mock` mode

`installer/repo.py`'s `MOCK` flag (set by `GISNIX_INSTALLER_MOCK=1`,
`--mock`, or `nix run .#installer -- --mock`) fakes disk listing and the
network check, and swaps the real install for
`installer_run.run_install_mock` — which still writes real host/user/flake
files to a temp dir (so you can inspect the actual generated Nix) but never
touches `/mnt`, disko, or `nixos-install`. Fastest loop for iterating on the
screens themselves: `nix develop` then `python3 -m installer --mock` runs
straight from the working tree, no derivation rebuild between edits
(`textual` is in the dev shell's python for exactly this).

## Why a `kz` command {#why-a-kz-command}

Every operator-facing tool in this repo goes through the `kz` dispatcher —
one manifest row, one wrapper script, three surfaces generated from it (see
[Architecture](architecture.md#the-kz-command-manifest)). The installer is
built the same way rather than as a hand-rolled `writeShellApplication`
pair: `packages.gisnix-installer` (what the ISO installs) is built from the
*same* `commands.json` row via `mkCommandDrv`, so there's exactly one
definition of what the installer needs, not two.
