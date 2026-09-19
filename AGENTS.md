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

## Bundles

A bundle is a directory under `software/` with a `bundle.json`.
Discovery walks the tree automatically, but every `.nix` file in that
directory has to be listed in `"modules"` or `"unclaimed"` — otherwise
`check-bundles.py` fails, and rightly so: a module nobody claims is a
module nobody installs, silently. `software/bundles.nix` (the discovery
code itself) has gone missing during a repo extraction before and
nothing caught it except a real `nixos-install` failing on a live
machine.

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
