# Building on gisnix

`lib.mkHost` and `lib.mkFleet` are exposed specifically so another flake can
build one host, or many, from gisnix's bundles, profiles and overlays while
keeping only its own `hosts/<name>` and `users/<name>` — no vendored copy of
`software/`, `profiles/`, or `overlays/`. This is how the installer's own
generated per-machine flake works, and how a bigger fleet flake works too.

For the day-to-day workflow (config picker, rebuilding, adding a second
machine) see [Building your fleet](../user/fleet.md). This page is the
underlying API.

## A single host

```nix
{
  inputs.gisnix.url = "github:kartoza/gisnix";
  outputs = { self, gisnix, ... }: {
    nixosConfigurations.myhost = gisnix.lib.mkHost "myhost" {
      hostPath = ./hosts/myhost;
    };
  };
}
```

`hostPath` points at a directory in *your own* repo, shaped like
`hosts/example/` (see [Adding a host](adding-a-host.md)). `gisnix.lib.mkHost`
wires in disko/agenix/home-manager/stylix, resolves your `config.nix`'s
bundle list against gisnix's registry, and applies gisnix's overlays — all
without your flake needing to know any of that exists.

## A fleet

```nix
{
  inputs.gisnix.url = "github:kartoza/gisnix";
  outputs = { self, gisnix, ... }: {
    nixosConfigurations = gisnix.lib.mkFleet ./hosts { };
  };
}
```

`mkFleet` scans `./hosts` for subdirectories carrying a `config.nix` (the
same convention `hostconfig.py`'s own host discovery uses) and calls
`mkHost` once per name found — add a host by adding a directory, not by
also editing `flake.nix`.

The second argument takes:

- `perHostArgs` — keyed by hostname, for the one host that needs something
  the others don't (`stableCosmic`, `extraModules`, its own
  `projectConfig` override):

  ```nix
  gisnix.lib.mkFleet ./hosts {
    perHostArgs.myhost.extraModules = [ ./hosts/myhost/something-extra.nix ];
  };
  ```

- `projectConfig` / `fleet` — see the next section. Set once here to apply
  to every host `mkFleet` builds, instead of repeating it per host.

A flake managing dozens of hosts doesn't have to use `mkFleet` at all —
calling `mkHost` in your own loop works exactly as well, and is worth doing
directly if your fleet has per-host machinery (a deploy-method registry,
hardware-specific extras) beyond what `mkFleet`'s `perHostArgs` covers.

## Your own `projectConfig` and `fleet`

`mkHost`/`mkFleet` default to gisnix's own `config.nix` and `hosts/fleet.nix`
— `example.com`, `nixosStateVersion = "26.05"`, no Hetzner/Keycloak/whatever
else your own fields are. Any host or module that reads a `projectConfig`
field gisnix's own `config.nix` doesn't have will hard-fail on a missing
attribute; any field both sides define (like `nixosStateVersion`) will
silently take gisnix's value instead of yours if you don't override it.

Supply your own:

```nix
gisnix.lib.mkHost "myhost" {
  hostPath = ./hosts/myhost;
  projectConfig = import ./config.nix;   # your own, real values
  fleet = import ./hosts/fleet.nix;      # your own, real machines
}
```

`fleet` matters even for a single host: gisnix's `services-system/
fleet-hosts.nix` (part of the always-on `services-system` bundle) reads it
to generate `/etc/hosts` entries for every machine it names — pass your own
so `ssh anotherhost` resolves correctly, or omit it if you don't maintain a
fleet registry at all (an empty `{ hosts = {}; }` is fine).

## Re-attaching a genericized module's private content

A few of gisnix's shared modules are deliberately generic where a real
value would have to be private — `services-system/ca-certificates.nix`
doesn't ship anyone's actual internal CA, it exposes an
`extraCA.certificateFiles` option (empty by default) instead. If your own
fleet needs one, `extraModules` re-attaches it exactly like any other
private addition:

```nix
gisnix.lib.mkHost "myhost" {
  hostPath = ./hosts/myhost;
  extraModules = [
    { extraCA.certificateFiles = [ ./resources/my-ca-chain.crt ]; }
  ];
}
```

## `gisnixRoot`: reaching gisnix's own profiles directly

`hostPath`'s own files (`default.nix`, `desktop.nix`, `services.nix`, ...)
receive `gisnixRoot` as a specialArg — this flake's own root, as an
absolute path. Use it instead of a `../../` path (which would resolve
against *your* repo, not gisnix's) to import one of gisnix's non-bundle
profiles directly:

```nix
{ gisnixRoot, ... }:
{
  imports = [
    (gisnixRoot + "/profiles/cosmic-desktop.nix")
  ];
}
```

This is for the handful of profiles that aren't bundle-driven (they turn on
an activation option, or pull in `hostPath`'s own `desktop.nix`/
`services.nix` — a bundle structurally can't do either). Bundle content
itself doesn't need this: `gisnix.lib.mkHost` already imports
`profiles/bundles.nix` from gisnix's own tree regardless of where `hostPath`
points, so a `bundles = [ "desktop-browsers" ]` entry in your `config.nix`
resolves correctly with no path juggling on your side at all.

## Your own `inputs`

`hostPath`'s files also receive an `inputs` specialArg — but by default it's
*gisnix's own* `inputs`, not yours. A host file referencing a flake input
your own flake declares (a vendored kernel, a private tool) fails with
"attribute missing" even though the input genuinely exists — it's just not
in the `inputs` this host file was handed.

```nix
gisnix.lib.mkHost "myhost" {
  hostPath = ./hosts/myhost;
  consumerInputs = inputs;   # your flake's own inputs, not gisnix's
}
```

`mkFleet` takes the same parameter, applied to every host it builds. This
only affects the `inputs` specialArg your own `hostPath` files see —
gisnix's internal use of its own inputs (disko, home-manager, its own
overlays) is unaffected either way.

## Known gotchas from a real migration

Two real failures, found migrating an existing, non-trivial fleet onto
`mkHost` — worth knowing before you hit them yourself.

**`nixpkgs.config` set directly, from more than one module.**
`nixpkgs.config.allowUnfreePredicate` and
`nixpkgs.config.permittedInsecurePackages` are bare, loosely-typed attrs
keys with no per-key merge behaviour — the module system silently keeps
only ONE definition if more than one module sets either directly. gisnix
avoids this internally via `kartoza.unfreePackages`/`kartoza.insecurePackages`
(`services-system/unfree.nix`), which are real `listOf str` options that
concatenate. If your own `extraModules` (or a private module you layer in)
sets `nixpkgs.config.allowUnfreePredicate` or
`nixpkgs.config.permittedInsecurePackages` directly instead of using those
two options, expect a package one of your OWN modules explicitly permits to
still refuse evaluation with "marked as insecure"/unfree — silently, no
error pointing at the real cause. Use `kartoza.unfreePackages`/
`kartoza.insecurePackages` from any module instead; they're additive
regardless of what else is declared.

**`boot.zfs.forceImportRoot` conflicting with an existing host's own
setting.** gisnix's `base` bundle sets this `true` unconditionally — it
fixes a real installer bug (the live ISO and the freshly-installed system
have different ZFS hostids on first boot). A host you're migrating that
predates disko — an existing install, hostid already consistent — likely
already sets this `false` in its own `hardware.nix`. Two plain (non-
`mkForce`) definitions of the same value is a hard eval error
("conflicting definition values"), not a silent one. Fix it in your own
host file with `lib.mkForce false`, not by changing gisnix's default (which
is correct for the fresh-install case every OTHER host relies on).

## Extending gisnix's tooling to your own bundles

There's no mechanism yet for a downstream flake to *add* modules to a
bundle name gisnix already defines — if you take `desktop-kartoza-apps` (or
whatever bundle) and gisnix's own copy is narrower than what you want,
add your own modules via `extraModules` rather than trying to extend the
bundle itself. Tracked as a real gap, not a design decision — a future
version may let a consumer register additional modules under an existing
bundle name.

## What's proven

- Building a host with `hostPath` outside gisnix's own tree — the
  `hostPath`/`gisnixRoot`/`fleet` specialArgs exist specifically to make
  this correct (see [Architecture](architecture.md)).
- `mkHost`/`mkFleet` accepting a real `projectConfig`/`fleet` override
  instead of gisnix's own placeholders.
- `mkHost`/`mkFleet` accepting a `consumerInputs` override, so a host file
  referencing an input only your own flake declares resolves correctly.
- A real fleet migration (three hosts, one with pre-existing hardware
  predating disko) — see the gotchas above, both found and fixed this way.
- `nix run github:kartoza/gisnix#configure -- <host>` and `#bundles`,
  run from inside a downstream flake's own directory with no gisnix
  checkout present at all — verified against a scratch directory outside
  any gisnix checkout. `configure.py`/`hostconfig.py` split "where the
  bundle catalogue lives" (gisnix's own tree, via a `GISNIX_ROOT`
  environment variable the nix-packaged command sets) from "where the
  target host's files live" (the caller's own working directory) —
  previously conflated under one path, computed from the script's own
  file location, which only worked by accident when both happened to be
  the same checkout.
- `docs-generate-hosts` (per-host reference pages) the same way — reads
  gisnix's published `docs/references/software.json` for package
  metadata, but runs `nix eval` and writes generated pages against the
  calling flake's own root.
- `nixos-rebuild switch --flake .#myhost` and editing `config.nix`'s
  bundle list by hand.

## What isn't wired up yet

- **Extending an existing bundle name from a downstream flake** — see
  above; `extraModules` is the workaround.
- **`gisnix create-host`** (adopting an already-installed machine) still
  assumes `utils/` and the target `hosts/` live in the same checkout —
  it wasn't part of this round of fixes, since the workflow it serves
  (bring a self-installed machine into a flake) doesn't apply to a
  flake generated by the installer, which already has a `hosts/<name>/`.
- **`docs-generate-software`/`-bundles`/`-commands` and `docs-build`/
  `-serve`** build gisnix's own public site and were never meant to run
  against a downstream flake's data — a consumer wanting its own docs
  site (real hostnames, private topology) should build a separate one,
  not try to feed private data through gisnix's public generator.
