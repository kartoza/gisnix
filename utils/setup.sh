#!/usr/bin/env bash
#
# setup — the Kartoza-branded bootable-USB setup wizard.
#
#   gisnix setup            # partition a disk, create a host + user, install
#   gisnix setup --mock     # same wizard, disks/network faked, no real
#                            # install step — safe to run anywhere, for
#                            # iterating on the screens themselves
#
# This is the SELF-driven wizard: someone sitting at the machine's own
# keyboard, booted from the ISO. It is a different tool from `gisnix install`,
# which is the ADMIN-driven path — nixos-anywhere over SSH into an
# already-booted live system. Both exist; they solve different problems
# (and the name collision is exactly why this one isn't also called
# "install" — it needs its own word).
#
# The wizard's own code lives in installer/ at the repo root (Textual), not
# under utils/ — that directory name predates this command's rename to
# `setup` and refers to what the wizard IS (an installer), not what you type.
# This file is just the same one-line wrapper shape every other `gisnix`
# command uses, so `setup` gets a flake app, a `gisnix` subcommand and a
# dev-shell binary for free, same as everything else in this manifest. See
# installer/app.py for the wizard itself, and installer/screens/bundles.py
# for why its software-selection step confirms a fixed default set rather
# than reusing THIS SAME repo's utils/lib/configure_tui.py in-process.
#
# Run two different ways, so it has to find its own repo root rather than
# assume the caller already cd'd there:
#   - `gisnix setup`      — gisnix already cd'd to the repo root; we're IN it.
#   - `setup`             — the ISO's environment.systemPackages entry,
#                           invoked from whatever directory a login shell
#                           happens to be in.
set -uo pipefail

# disko and nixos-install need root; --mock fakes both and touches neither,
# so it's the one invocation that genuinely doesn't need this. Re-execs
# the same script under sudo rather than relying on the caller to
# remember it themselves — the live ISO's `nixos` user has passwordless
# sudo (wheelNeedsPassword = false), so this never actually prompts there.
# A developer running `--mock` from their own `nix develop` shell is
# unaffected either way: --mock always skips the re-exec, sudo or not.
if [ "$(id -u)" -ne 0 ]; then
  mock=false
  for arg in "$@"; do
    [ "$arg" = "--mock" ] && mock=true
  done
  if [ "$mock" = false ]; then
    exec sudo "$0" "$@"
  fi
fi

root="${GISNIX_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
if [ -z "$root" ]; then
  for candidate in /etc/gisnix /iso/gisnix /home/gisnix; do
    [ -f "$candidate/brand.nix" ] && root="$candidate" && break
  done
fi
if [ -z "$root" ] || [ ! -f "$root/brand.nix" ]; then
  echo "setup: cannot find the gisnix checkout (looked for \$GISNIX_ROOT, git root, /etc/gisnix, /iso/gisnix, /home/gisnix)" >&2
  exit 1
fi
export GISNIX_ROOT="$root"
cd "$root" || exit 1

clear
# --format=symbols pins chafa to plain ANSI symbol output rather than
# whatever it auto-detects — harmless here since the real console already
# picks symbols on its own, but a guard against a terminal that falsely
# advertises Kitty/Sixel support and gets a binary protocol payload dumped
# as garbage text instead of a picture.
chafa --size=36x resources/kartoza-logo.png --format=symbols 2>/dev/null || true
exec python3 -m installer "$@"
