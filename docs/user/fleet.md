# Building your fleet

You've installed gisnix once and have a working machine. This is what to do
next: live with that one host productively, then grow to two, ten, or
however many machines you end up running — while keeping gisnix's own
updates flowing in for free.

## What you actually have

The installer left you `~/nixos-config`: a small flake that pins gisnix as
an input and points at your one host.

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

Every package, every desktop profile, every overlay comes from gisnix. Your
own repo holds exactly three things: `hosts/myhost/` (its hardware, disk
layout, and which bundles it takes), `users/` (your account, your SSH
key), and this `flake.nix` gluing the two to gisnix. That's the whole
point — gisnix carries the opinion about what a good GIS workstation looks
like, your repo carries the facts about your own machines.

## Living with one host

```bash
cd ~/nixos-config
nix run github:kartoza/gisnix#configure -- myhost
```

Ticks bundles on and off, shows you a diff, writes nothing until you
confirm. No gisnix checkout needed — this reads gisnix's bundle registry
directly from the flake input and edits your own `hosts/myhost/config.nix`
in place. `#bundles` (no host argument) is the read-only version — what
exists, what's in it, what implies what.

```bash
sudo nixos-rebuild switch --flake .#myhost
```

is the always-available fallback if you'd rather hand-edit `config.nix` —
every bundle is listed there, commented out, uncomment a line to take it.

```bash
gisnix update
```

pulls in whatever's changed upstream — new gisnix commits your `flake.lock`
hasn't seen yet, most immediately COSMIC itself, which tracks
nixos-unstable rather than the stable channel your first boot used (see
the quickstart's note on why that trade exists). Run `nix flake update
gisnix` first if `gisnix update` alone doesn't pick up a change you know
landed upstream — that's the one-line version of "update this pin."

## Making it *your* fleet's repo

Before adding a second machine, put `~/nixos-config` somewhere durable:

```bash
cd ~/nixos-config
git init
git add -A
git commit -m "first host"
git remote add origin git@github.com:you/nixos-config.git
git push -u origin main
```

This repo is now the private layer sitting on top of gisnix — the same
relationship [kartoza/nix-config](https://github.com/kartoza/nix-config)
has to gisnix itself, just smaller. Nothing about it is gisnix-specific:
it's a plain git repo you own outright.

## Adding a second machine

Boot the gisnix installer on the new machine and go through the wizard as
before — it'll generate its own small `hosts/<name2>/` the same way it did
the first time. What's different this time is where that directory ends
up: **move it into your existing repo** rather than leaving it as its own
standalone flake.

```bash
# on the new machine, before or after its own first rebuild:
scp -r hosts/name2 you@your-git-host:~/nixos-config-checkout/hosts/
scp users/name2.nix you@your-git-host:~/nixos-config-checkout/users/   # if it added a new user
```

(Or copy by hand however suits you — a USB stick, `rsync`, pasting into an
editor. The installer's generated files have no host-specific magic beyond
what's readable in `hosts/name2/config.nix`.)

Then, in your fleet repo, either add a second line:

```nix
nixosConfigurations.name2 = gisnix.lib.mkHost "name2" {
  hostPath = ./hosts/name2;
};
```

or switch to `mkFleet`, which discovers every `hosts/*/config.nix` for you
— worth doing once you're past two or three hosts:

```nix
outputs = { self, gisnix, ... }: {
  nixosConfigurations = gisnix.lib.mkFleet ./hosts { };
};
```

Commit, push, and `nixos-rebuild switch --flake .#name2` on the new
machine against your real repo (not the installer's throwaway one).

!!! note "Why this is manual right now"
    `gisnix create-host` — the command for adopting an already-installed
    machine into a flake — is designed to run from a single checkout that
    has both gisnix's own tooling and your `hosts/` together, which a thin
    downstream repo deliberately doesn't have. Copying the generated
    `hosts/<name>/` directory across by hand is the honest current
    answer, not a workaround for a bug — see [Building on
    gisnix](../developer/downstream-flakes.md#what-isnt-wired-up-yet) for
    where this is tracked.

## Keeping private things private

Two kinds of content never belong in gisnix, and both attach to
`gisnix.lib.mkHost`/`mkFleet` the same way — `extraModules`:

**Your own `projectConfig` and `fleet` registry.** gisnix's own defaults
are placeholders (`example.com`, a generic `nixosStateVersion`). Supply
your real ones once your fleet has values worth keeping straight —
your actual domain, and (if you want `ssh othermachine` to resolve
without a hosts-file entry you maintain by hand) a real fleet registry:

```nix
gisnix.lib.mkFleet ./hosts {
  projectConfig = import ./config.nix;
  fleet = import ./hosts/fleet.nix;
};
```

**Anything a shared gisnix module deliberately doesn't carry.** A few of
gisnix's modules are generic on purpose where a real value would have to
be private — trusting an internal CA certificate is the clearest example:
gisnix's `services-system` bundle exposes an `extraCA.certificateFiles`
option, empty by default, rather than shipping anyone's actual chain.

```nix
gisnix.lib.mkHost "myhost" {
  hostPath = ./hosts/myhost;
  extraModules = [
    { extraCA.certificateFiles = [ ./resources/my-ca-chain.crt ]; }
  ];
};
```

The same pattern covers anything else specific to you: a private script, an
internal-only application, a fleet-wide VPN dispatcher. Small modules in
your own repo, layered on via `extraModules`, never touching gisnix's tree.
[Building on gisnix](../developer/downstream-flakes.md) has the full
reference for `gisnixRoot`, per-host overrides via `mkFleet`'s
`perHostArgs`, and what's proven to work versus still a known gap.

## Contributing back

If a fix or a bundle you built for your own fleet is generically useful —
not tied to your own hostnames, secrets, or internal services — it likely
belongs in gisnix itself rather than staying private. `AGENTS.md` in
gisnix's own repo covers the rules of the road (bundle conventions, what
the ISO does and doesn't ship, docs voice); a PR against
[kartoza/gisnix](https://github.com/kartoza/gisnix) is the way in. Every
fleet running gisnix gets the improvement the next time it updates the
pin — that's the whole reason to keep the split between "opinion" and
"your machines" honest in the first place.
