# Building on gisnix

`lib.mkHost` is exposed specifically so another flake can build a host from
gisnix's bundles, profiles and overlays while keeping only its own
`hosts/<name>` and `users/<name>` — no vendored copy of `software/`,
`profiles/`, or `overlays/`. This is how the installer's own generated
per-machine flake works, and it's the intended shape for Kartoza's internal
fleet (`nix-config`) too.

## The shape

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

`extraModules` is there for anything host-specific gisnix doesn't need to
know about:

```nix
gisnix.lib.mkHost "myhost" {
  hostPath = ./hosts/myhost;
  extraModules = [ ./hosts/myhost/something-extra.nix ];
}
```

## What's proven

- Building a host this way, with `hostPath` outside gisnix's own tree —
  the `hostPath`/`gisnixRoot`/`fleet` specialArgs exist specifically to make
  this correct (see [Architecture](architecture.md)).
- `nixos-rebuild switch --flake .#myhost` and editing `config.nix`'s bundle
  list by hand.

## What isn't wired up yet

`gisnix configure`'s interactive picker (and the rest of the `utils/` tooling)
assumes it's running from a checkout that has *both* the `utils/`
machinery *and* the target host's directory in the same tree —
`utils/lib/hostconfig.py`'s `REPO_ROOT` is computed from its own file
location, and a host directory lookup (`hosts/<name>/config.nix`) is
resolved relative to that same root. That's exactly true for gisnix's own
`hosts/example/` and for nix-config (which keeps `utils/` and `hosts/`
together on purpose), but it is **not** true for a standalone tiny flake
like the one the installer generates: it has `hosts/<name>/` but no
`utils/` at all.

Practically: editing `config.nix` by hand and rebuilding always works from
a tiny flake. The interactive `gisnix configure` menu does not, yet — making it
work would mean teaching `hostconfig.py` to resolve the bundle *catalogue*
from gisnix (wherever the script lives) but the *target host* from the
caller's own working directory, which are currently conflated under one
`REPO_ROOT`. Tracked as a known gap, not a design decision.
