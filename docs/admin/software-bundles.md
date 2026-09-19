# Software bundles

A **bundle** is a directory under `software/` carrying a `bundle.json` next
to the NixOS modules it describes. A host names the bundles it wants in
`hosts/<name>/config.nix`:

```nix
bundles = [
  "base"
  "desktop-environments-cosmic"
  "desktop-browsers"
  "services-system"
];
```

That's the installer's default set — a minimal base system plus a minimal
COSMIC desktop. Everything else in the registry is listed too, commented
out, right there in the file, so `config.nix` doubles as its own menu. See
[the full bundle reference](../references/bundles.md) for every bundle that
exists and what it holds.

## Changing what's installed

Uncomment (or add) a bundle name, then rebuild:

```bash
sudo nixos-rebuild switch --flake .#<name>
```

Comment one out and rebuild to remove it. `base` and `services-system` are
load-bearing (ZFS root and its bootloader; audio, certificates, hardening)
— removing them doesn't shrink the install, it breaks it.

## Implications

Some bundles imply others: taking `desktop-gis` (QGIS) automatically pulls
in `desktop-environments-cosmic`, because QGIS needs a desktop to display
in. You never have to work that out by hand — `profiles/bundles.nix`
resolves the full closure of implications at eval time. The
[bundle reference](../references/bundles.md) shows what implies what.

## Where the picker fits in

On a full gisnix checkout (not the tiny per-machine flake the installer
generates), `kz configure` gives you the same bundle selection as an
interactive menu — search, tick boxes, see what each thing installs before
committing. It's the exact same picker the installer's own software step
opens. See [the installer](../developer/installer.md) for how that's wired.
