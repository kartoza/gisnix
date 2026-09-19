#!/usr/bin/env bash
#
# installer — the Kartoza-branded bootable-USB installer wizard.
#
#   gisnix installer            # partition a disk, create a host + user, install
#   gisnix installer --mock     # same wizard, disks/network faked, no real
#                            # install step — safe to run anywhere, for
#                            # iterating on the screens themselves
#
# This is the SELF-driven installer: someone sitting at the machine's own
# keyboard, booted from the ISO. It is a different tool from `gisnix install`,
# which is the ADMIN-driven path — nixos-anywhere over SSH into an
# already-booted live system. Both exist; they solve different problems.
#
# The wizard's own code lives in installer/ at the repo root (Textual), not
# under utils/ — this file is just the same one-line wrapper shape every
# other `gisnix` command uses, so `installer` gets a flake app, a `gisnix`
# subcommand and a dev-shell binary for free, same as everything else in
# this manifest. See installer/app.py for the wizard itself, and
# installer/screens/bundles.py for how its software-selection step reuses
# THIS SAME repo's utils/lib/configure_tui.py rather than a second
# implementation.
#
# Run two different ways, so it has to find its own repo root rather than
# assume the caller already cd'd there:
#   - `gisnix installer`      — gisnix already cd'd to the repo root; we're IN it.
#   - `gisnix-installer`  — the ISO's environment.systemPackages entry,
#                           invoked from whatever directory a login shell
#                           happens to be in.
set -uo pipefail

root="${GISNIX_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
if [ -z "$root" ]; then
  for candidate in /etc/gisnix /iso/gisnix /home/gisnix; do
    [ -f "$candidate/brand.nix" ] && root="$candidate" && break
  done
fi
if [ -z "$root" ] || [ ! -f "$root/brand.nix" ]; then
  echo "installer: cannot find the gisnix checkout (looked for \$GISNIX_ROOT, git root, /etc/gisnix, /iso/gisnix, /home/gisnix)" >&2
  exit 1
fi
export GISNIX_ROOT="$root"
cd "$root" || exit 1

clear
chafa --size=48x resources/kartoza-logo.png 2>/dev/null || true
exec python3 -m installer "$@"
