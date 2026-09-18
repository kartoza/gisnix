#!/usr/bin/env bash
#
# shell-banner — what you see on entering the development environment.
#
# Lives here rather than inline in utils/develop.nix for two reasons.
#
# 1. The project rule: no code embedded in nix files. The shellHook had grown
#    to forty lines of shell inside a Nix string, with '' escaping on every
#    variable.
#
# 2. direnv never ran it. `use flake` evaluates the dev environment and
#    captures the shellHook's output — it has to, or stray output would
#    corrupt the environment diff it applies — and .envrc discards stderr on
#    top of that. So anyone entering the project through direnv, which is the
#    normal way, saw nothing at all. A standalone script can be called from
#    .envrc and write to the terminal directly.
#
# Safe to run any time: it only prints.
set -uo pipefail

ROOT="${NIX_CONFIG_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" 2> /dev/null || exit 0

CYAN=$'\033[38;2;83;161;203m'
GRAY=$'\033[90m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

BANNER="$ROOT/resources/kartoza-nixos-configuration.png"

# Cache directory, used for the fleet dashboard below.
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/kartoza-nix-config"

# Width follows the terminal, capped at 96 columns so the banner does not
# become a mural on a wide monitor, and floored at 40 so a narrow split still
# gets something legible. chafa preserves aspect inside the box it is given,
# and the image is about 3:1, so width is the dimension that matters.
#
# COLUMNS is not exported into every context this runs in, so ask the terminal.
banner_w="${COLUMNS:-0}"
[ "$banner_w" -gt 0 ] || banner_w=$(tput cols 2> /dev/null || echo 80)
banner_w=$((banner_w - 4))
[ "$banner_w" -gt 96 ] && banner_w=96
[ "$banner_w" -lt 40 ] && banner_w=40

if [ -f "$BANNER" ] && command -v chafa > /dev/null 2>&1; then
  # --format symbols is deliberate, not an accidental downgrade.
  #
  # Left to itself chafa detects the terminal and emits Kitty or Sixel
  # graphics — a binary payload preceded by a protocol handshake that needs
  # stdout to BE the terminal. Here it is not: .envrc writes to /dev/tty
  # because direnv has already claimed stdout, so chafa negotiated a protocol
  # it could not complete and the banner rendered as nothing at all. Symbol
  # output is plain ANSI text with no negotiation, so it works down every
  # path this script is called from.
  chafa "$BANNER" --size="${banner_w}x16" --format=symbols --colors=256 || true
  echo
elif [ ! -f "$BANNER" ]; then
  echo "  ${GRAY}(banner image missing: ${BANNER#"$ROOT"/})${RESET}"
elif ! command -v chafa > /dev/null 2>&1; then
  echo "  ${GRAY}(chafa not on PATH — no banner)${RESET}"
fi

# Who is up, right now. Reachability only — `kz inventory` is the version that
# waits on SSH for unit health.
#
# Cached for a minute. The probe already runs concurrently with a one-second
# timeout, but that is still about a second, and this fires on every entry
# into the project: a `cd` in and out costs it twice. A minute-old answer to
# "is waterfall up" is fine for a banner, and `kz fleet` always re-probes.
FLEET_CACHE="$CACHE_DIR/fleet-status.txt"
if [ -f utils/fleet-status.sh ]; then
  mkdir -p "$CACHE_DIR"
  if [ -f "$FLEET_CACHE" ] && [ -z "$(find "$FLEET_CACHE" -mmin +1 2> /dev/null)" ]; then
    cat "$FLEET_CACHE"
  else
    bash utils/fleet-status.sh 2> /dev/null | tee "$FLEET_CACHE"
  fi
fi

cat <<EOF

  ${BOLD}All operator commands are namespaced under ${CYAN}kz${RESET}${BOLD}.${RESET}

  ${GRAY}▶${RESET}  ${CYAN}kz${RESET}                  the full command list, grouped by lifecycle
  ${GRAY}▶${RESET}  ${CYAN}kz fleet${RESET}            refresh the dashboard above
  ${GRAY}▶${RESET}  ${CYAN}kz inventory${RESET}        unit health and generations, over SSH (slower)
  ${GRAY}▶${RESET}  ${CYAN}kz update${RESET}           rebuild this machine
  ${GRAY}▶${RESET}  ${CYAN}kz check waterfall${RESET}  one host, in depth

  ${GRAY}docs${RESET}   ${CYAN}kz docs-serve${RESET} (localhost:8000)   ${CYAN}kz docs-build${RESET}   ${CYAN}kz docs-pdf${RESET}
  ${GRAY}qa${RESET}     ${CYAN}kz lint${RESET}   ${CYAN}kz test${RESET}   ${CYAN}kz hooks${RESET}

  ${GRAY}Outside this shell:${RESET} ${CYAN}nix run .#kz -- <command>${RESET}
EOF
