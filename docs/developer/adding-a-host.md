# Adding a host by hand

The installer is the normal path (see the [quickstart](../user/quickstart.md)),
but a host is just files — nothing about it requires the wizard.

`hosts/example/` is the reference shape. Copy it:

```bash
cp -r hosts/example hosts/myhost
```

Then edit, in order:

1. **`config.nix`** — the bundle list (uncomment what you want; every
   bundle is listed, see [the reference](../references/bundles.md)),
   `locale`, and `bootTheme`.
2. **`default.nix`** — usually just `networking.hostName` needs to change;
   the imports (locale module, core profiles) stay as-is unless you're
   changing locale.
3. **`hardware.nix`** — real hardware needs real detection. The shipped
   version is a generic virtio/UEFI profile for VM testing; for bare metal,
   replace it with what `nixos-generate-config` produces on the target (or
   adapt from a real host's `hardware.nix` if you're migrating one). Either
   way, replace `networking.hostId` with a fresh value
   (`head -c 8 /etc/machine-id` on the target) — the example's own value is
   exactly that, an example, and ZFS needs every host to have a different
   one.
4. **`disks.nix`** — pick a storage template (see
   [Storage modes](../admin/storage-modes.md) and
   [Architecture](architecture.md#storage-templates)) and set the real
   device path(s).
5. **`users/<name>.nix`** — copy `users/example.nix`, set a real username
   and your own SSH public key(s).
6. **`hosts/fleet.nix`** — add an entry if you want this host known to
   others (see [Administration](../admin/index.md#fleet-metadata)); skip
   this entirely for a single standalone machine.

Then build it:

```bash
nix run .#myhost-vm      # QEMU, headless — fast config check
sudo nixos-rebuild switch --flake .#myhost   # on the real machine
```

## Registering a test

`tests/test-example.nix` is the pattern for a NixOS integration test — copy
it, point `_module.args.hostname` and the imported user file at your host,
and add an entry to `tests.nix` so `nix flake check` picks it up.
