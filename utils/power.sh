#!/usr/bin/env bash
#
# power — why is this machine hot, and what is it spending watts on?
#
#   gisnix power              # profile now
#   gisnix power --seconds 5  # sample the processor for longer
#   gisnix power --watch      # refresh until interrupted
#   gisnix power --json       # machine-readable, for graphing over time
#
# Read-only. It reads sysfs and /proc, samples briefly, and reports
# temperatures, clocks, power draw and what is running — then says which of
# those look like they cost heat, and prints the Nix that would change each.
#
# NOTHING IS APPLIED. The right answer depends on what the machine is for: a
# laptop on a train and a build host want opposite settings, so every finding
# ends in a suggestion you decide about.
#
# Needs no root and no vendor tools. A machine missing a sensor reports one
# fewer line rather than failing, which is what makes it usable anywhere.
#
# The work is in utils/power.py; this wrapper exists because the command
# manifest builds each command from one shell file.
set -uo pipefail
exec python3 "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/utils/power.py" "$@"
