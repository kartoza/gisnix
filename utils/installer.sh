#!/usr/bin/env bash
#
# installer — the Kartoza-branded bootable-USB installer wizard.
#
#   kz installer            # partition a disk, create a host + user, install
#   kz installer --mock     # same wizard, disks/network faked, no real
#                            # install step — safe to run anywhere, for
#                            # iterating on the screens themselves
#
# This is the SELF-driven installer: someone sitting at the machine's own
# keyboard, booted from the ISO. It is a different tool from `kz install`,
# which is the ADMIN-driven path — nixos-anywhere over SSH into an
# already-booted live system. Both exist; they solve different problems.
#
# The wizard's own code lives in installer/ at the repo root (Textual), not
# under utils/ — this file is just the same one-line wrapper shape every
# other `kz` command uses, so `installer` gets a flake app, a `kz`
# subcommand and a dev-shell binary for free, same as everything else in
# this manifest. See installer/app.py for the wizard itself, and
# installer/screens/bundles.py for how its software-selection step reuses
# THIS SAME repo's utils/lib/configure_tui.py rather than a second
# implementation.
set -uo pipefail

clear
chafa --size=48x resources/kartoza-logo.png 2>/dev/null || true
exec python3 -m installer "$@"
