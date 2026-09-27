# Working on gisnix

There are two different things you might be doing, and they want different
loops. One is **changing gisnix itself** — a bundle, a module, the installer,
these docs. The other is **testing a gisnix change against your own
machines** before you release it. The first needs nothing but the gisnix
repo. The second has a fast path that never touches GitHub, and it is the one
worth learning first because it removes all the waiting.

## Where the code lives

gisnix is its own git repository. Check it out wherever suits you — keeping it
inside your fleet's own config repo (git-ignored there) is convenient and
keeps the override path below short. Your fleet consumes gisnix as a flake
*input* (`github:kartoza/gisnix`), so editing your local checkout does **not**
change what your fleet builds until you push and update. That is by design —
and it is exactly why the override loop exists.

## Loop 1 — changing gisnix itself

Most of the time you are working inside the gisnix repo, and you do not need
your fleet at all. gisnix is self-contained: it ships an `example` host and
its own build, VM and test tooling, and Nix reads your **working tree**
directly — no commit required to try something.

```bash
cd gisnix
# edit a bundle / module / the installer / a doc...

# Does it build? (the same thing a real install builds, and what CI gates on)
nix build .#nixosConfigurations.example.config.system.build.toplevel

# Does every bundle still evaluate? (catches unfree/insecure across all bundles)
./utils/check-bundle-eval.sh

# See it run
gisnix vm example --boot --screenshots
```

The `example` host is the stand-in for a real install; the build and the
bundle-eval are the same checks the release pipeline runs. A dirty-tree
warning from Nix is normal here — that is it reading your uncommitted edits.

## Loop 2 — trying a change on your own machine

When you want a gisnix change on a real host — your laptop, a fleet machine —
*before* releasing it, do not push and re-lock. Override the input to point
at your local checkout:

```bash
cd ~/your-fleet      # your own nix-config
sudo nixos-rebuild switch --flake .#<host> \
  --override-input gisnix path:./gisnix
```

That builds `<host>` against your local gisnix checkout, uncommitted edits and
all, with no GitHub round-trip. Drop the `--override-input` and you are back
on the published gisnix instantly — nothing on disk changed, so there is
nothing to undo.

!!! tip "path: vs a committed override"
    `path:./gisnix` copies your working tree, so it includes uncommitted
    edits — ideal while iterating. If that copy is slow (a large checkout),
    commit first and use `--override-input gisnix ./gisnix`, which uses the
    git tree and respects `.gitignore`.

## Loop 3 — shipping it

Once it builds, evaluates and behaves, publish — this is the only step that
touches GitHub, and you only reach it when the change is proven:

1. Commit and push gisnix. If it is release-worthy, tag it (see
   [Releasing](releasing.md), which runs the build and bundle-eval gates before
   it will publish).
2. In your fleet flake, adopt the published version:

    ```bash
    nix flake update gisnix
    ```

   Keep that lock change in its own commit — lockfiles are sacred.

## Which loop, when

| You are… | Use |
| --- | --- |
| changing a bundle, module, installer or doc | **Loop 1** — build/eval/VM the `example` host |
| wanting that change on a real machine to live with it | **Loop 2** — `--override-input`, no push |
| done, and it is proven | **Loop 3** — push, tag, then `nix flake update gisnix` |

## See also

- [Checks and hooks](checks.md) — every check that runs on commit, on push and
  at release, and what each one verifies.
- [Architecture](architecture.md) — how the pieces fit together.
- [Building on gisnix](downstream-flakes.md) — consuming gisnix from your own
  flake.
- [Releasing](releasing.md) — cutting a version and what the gates check.
