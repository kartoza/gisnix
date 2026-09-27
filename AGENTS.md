# AGENTS.md

Notes for anyone — human or AI — working on gisnix, collected from things
that broke during development. Read
[docs/developer/index.md](docs/developer/index.md) first for how the repo
is actually put together.

## Verification that doesn't need a nix daemon

```bash
python3 utils/check-bundles.py       # every software/ module is claimed by a bundle
python3 utils/check-hostconfig.py    # the config.nix editor round-trips cleanly
python3 utils/check-iso-contents.py  # every relative ref a baked module makes is also baked
mkdocs build --strict
nix-instantiate --parse <file.nix>
shellcheck <file.sh>
```

If you're an agent in a sandboxed environment, `nix build`/`nix eval`/
`nix flake lock` will probably fail with something like "cannot connect
to socket at .../daemon-socket/socket". That's the sandbox, not a bug.
Run the checks above instead and say plainly which kind of verification
you actually did — don't imply a build succeeded when all you ran was a
syntax check.

## eval is NOT build — build the install target before every release

This is the rule that keeps getting broken, each time shipping a release
that fails on real hardware at `sudo setup`.

`nix eval .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath`
proves the configuration **evaluates**. It does **not** prove it **builds**.
Many derivations only fail when actually built — the biggest offender is the
kanata config `.kdb`, which is validated by running `kanata --check` inside a
build, so a config that uses a `cmd` action without `danger-enable-cmd yes`
evaluates perfectly and then fails the build with:

    [ERROR] Error in configuration ...kanata-keyboard-config.kdb
    help: To use cmd you must put in defcfg: danger-enable-cmd yes.
    INSTALL FAILED: building the system failed

An install runs `nix build` of the host toplevel; the release workflow only
built the *ISO* (which does not build any host), so this class of break
sailed straight through. It has now shipped more than once.

Rules:

- **Before tagging any release, BUILD — not eval — the example host
  toplevel**, which is what a default install builds:

  ```bash
  nix build .#nixosConfigurations.example.config.system.build.toplevel
  ```

  This is also a **pre-push git hook** (`.pre-commit-config.yaml`, `pre-push`
  stage — run `gisnix hooks` once to install it), and it runs in CI
  (`.github/workflows/build-hosts.yml`, and a gate in `release.yml`). All three
  call the one script, `utils/check-example-builds.sh`. A green `nix eval` /
  `nix flake check` / `nix-instantiate --parse` is NOT enough.
- **The other direction: build is not eval-of-everything.** The example host
  builds, but it enables only a minimal bundle set — so an unfree or insecure
  package in a bundle it does NOT take (e.g. `googleearth-pro` in `desktop-gis`,
  which is both) never gets evaluated by the build above and breaks the install
  instead. unfree/insecure/assertion errors throw at EVAL, so
  `utils/check-bundle-eval.sh` evaluates the example host with every non-opt-in
  bundle enabled — a cheap, comprehensive net for that class. Like the build
  gate it is a `pre-push` hook and runs in `build-hosts.yml` / `release.yml`.
  A sibling, `utils/check-commands-eval.sh`, evaluates every command app so a
  bad `commands.json` row can't ship either. All three gates are the `pre-push`
  stage in `.pre-commit-config.yaml` — `gisnix hooks` installs them.
- If a change touches any host's software (a bundle, a module, the kanata
  config, a service), the build above is mandatory evidence before you claim
  it works or cut a release. Say which you ran: eval or build.
- **`danger-enable-cmd yes` in the default kanata config
  (`software/services/device/input-kanata/kanata-keyboard.nix`) is
  unconditional and must stay so** — that config always emits a `cmd` (the
  herdr record-toggle sound). It was once gated on `voxtypePtt || emailScript`
  and flipping `voxtypePtt` to false broke every install. Do not re-narrow it.

## Bundles

A bundle is a directory under `software/` with a `bundle.json`.
Discovery walks the tree automatically, but every `.nix` file in that
directory has to be listed in `"modules"` or `"unclaimed"` — otherwise
`check-bundles.py` fails, and rightly so: a module nobody claims is a
module nobody installs, silently. `software/bundles.nix` (the discovery
code itself) has gone missing during a repo extraction before and
nothing caught it except a real `nixos-install` failing on a live
machine.

## The installer's explicit closure copy is load-bearing — never revert it

`installer/installer_run.py` does NOT run `nixos-install --flake`. It
builds the system toplevel, copies its closure into `/mnt` with an
explicit `nix copy --no-check-sigs --to /mnt <toplevel>`, and only then
runs `nixos-install --system <toplevel> --no-channel-copy`. This is not
an accident or a style choice — it is the fix for a real, reproduced
bug.

`nixos-install`'s own build step (`nix build --store /mnt
--extra-substituters "auto?trusted=1" ...#toplevel`) does not reliably
copy the system closure into the target store. On a real install it left
`/mnt` without the toplevel entirely — the log showed only the ~10 MiB
flake source landing in `/mnt`, never the multi-GB system — so the
system profile pointed at a path absent from `/mnt/nix/store` and the
post-install chroot died with:

    installing the boot loader...
    chroot: failed to run command '/nix/var/nix/profiles/system/activate': No such file or directory
    INSTALL FAILED: command failed (127)

Reproduced in isolation: `nix build --store <target>` leaves the
toplevel absent; a plain `nix copy --to <target> <toplevel>` places the
full runtime closure with `activate`. That is why the copy is explicit.

Rules for anyone touching the install flow:

- Do NOT "simplify" the build + `nix copy` + `--system` sequence back
  into a single `nixos-install --flake`. That reintroduces the bug.
- If you change it, you must prove — with a real `sudo setup` install (or
  `gisnix test-install` end to end) that reaches a booting system — that
  the closure still lands in `/mnt` and the chroot finds `activate`. A
  syntax check or an eval is NOT sufficient evidence here.
- The `nix copy` stages the closure in the live environment's own store
  first (RAM-backed on the ISO). If you rework it for low-memory targets,
  the goal is to substitute straight to `/mnt` — not to drop the explicit
  copy.

## The ISO only ships what installer.nix says it ships

A fresh install evaluates the flake against whatever `installer.nix`'s
`isoImage.contents` actually copied onto the image, not against your
working checkout. `dotfiles/` learned this the hard way: plenty of
modules read from it with `builtins.readFile ../../dotfiles/whatever`,
that resolves fine on disk, and none of it existed on the ISO until
someone added the directory to the content list. `check-iso-contents.py`
walks every baked `.nix` file and checks its relative references land
somewhere also baked — run it after touching the content list or adding
any relative-path reference under `software/`, `overlays/`, `profiles/`,
`users/`, `hosts/`, or `templates/`.

## Keep shell script out of .nix files

A `loginShellInit` or `shellHook` string longer than a line or two goes
in `utils/*.sh` and gets called from the module. See
`utils/shell-banner.sh` (called from `develop.nix`) or
`utils/live-banner.sh` (called from `installer.nix`). Multi-line Nix
strings don't get syntax highlighting or shellcheck, and every `''`
interpolation is a place to get it wrong.

## Unfree packages

Add the package name to `kartoza.unfreePackages`
(`software/services/system/unfree.nix`) rather than setting
`nixpkgs.config.allowUnfreePredicate` directly in your own module. That
option is a function, and the module system keeps exactly one
definition when several modules set it — nine files in this repo used to
each declare their own predicate, and eight of them just lost, silently.
`kartoza.unfreePackages` is a list, so it merges across every
contributor instead.

## Console rendering on the live ISO

The console font (Terminus, `ter-v32n`) has ordinary box-drawing
(U+2500–2518) but not the block-element range (U+2580–259F) — the one
Textual's `tall`/`round`/`block` border styles use, and the one `chafa`'s
default symbol renderer draws images with. If you're adding anything
that prints to that console, check which glyphs it actually needs before
trusting how it looks in your own terminal. For `chafa` specifically,
pass `--format=symbols` so it can't fall back to auto-detecting Kitty or
Sixel graphics support and dumping a binary protocol payload as text on
a console that has neither.

## Lockfiles

`flake.lock` updates need a real nix daemon, which most sandboxed agent
environments don't have. If one's needed, write out the exact command,
hand it to the user to run outside the sandbox, and review the resulting
diff rather than guessing at what it should contain. They're their own
commit, separate from whatever prompted the update.

## The command manifest

Every operator command is one row in `utils/commands.json`, and
`mkCommandDrv` in `flake.nix` turns that single row into three things:
`nix run .#<name>`, the `gisnix <name>` dispatch, and the binary that
ships on the ISO/dev shell. A new command is a manifest row plus a
script under `utils/` — not a flake app defined on its own, which would
mean two definitions of the same thing drifting apart. See
`docs/developer/architecture.md`.

## Default-on bundles

`installer/state.py`'s `DEFAULT_BUNDLES` and `utils/gen-host-config.py`'s
`ACTIVE` list have to match — a comment in both says so. Before adding
something to either, check what its bundle actually drags in.
`services-device-input-kanata` exists as its own bundle, split out of
`services-device-input`, specifically so kanata could go default-on
without also defaulting on OpenRazer's kernel module and the Bazecor/
Piper vendor tools, none of which most machines have hardware for.

## Docs voice

Write like a 90s technical manual, or like a GIS professional
explaining something to a colleague — not like marketing copy, and not
like a chatbot being enthusiastic about box-drawing characters. Nothing
about the private Kartoza fleet, its hosts, or its staff belongs here;
this repo is read by people who've never heard of any of that and don't
need to.
