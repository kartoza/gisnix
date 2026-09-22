#!/usr/bin/env bash
#
# live-banner — what you see logging into the booted installer ISO.
#
# Lives here rather than inline in installer.nix's programs.bash.loginShellInit
# for the same reason utils/shell-banner.sh exists separately from
# utils/develop.nix: the project rule is no code embedded in nix files, and a
# banner with a table in it is a lot more than a one-line echo.
#
# Called with the cwd already /home/gisnix (installer.nix does the `cd`
# before invoking this) — resources/ and the rest of the checkout are right
# there, no path hunting needed.
#
# The box-drawing and arrow glyphs below are safe on THIS console specifically
# because installer.nix sets console.font to a Terminus "v"-charset PSF — the
# broad-Unicode-coverage variant. Colour is safe here too: the chafa logo
# above already renders in full 24-bit colour on this same console (chafa
# correctly detects it can't do Kitty/Sixel graphics there and falls back to
# ANSI symbols on its own), so plain text using the same escape codes has
# nothing further to prove. brand.nix's own accent palette, not colours
# invented for this one script — teal for structure, orange for the "do
# this" arrows, blue for the commands themselves.
#
# Safe to run any time: it only prints.
set -uo pipefail

TEAL=$'\033[38;2;6;150;154m'   # brand.nix primary — the Kartoza mark
BLUE=$'\033[38;2;86;159;198m'  # brand.nix secondary
ORANGE=$'\033[38;2;223;158;47m' # brand.nix accent
BOLD=$'\033[1m'
RESET=$'\033[0m'

clear
# --symbols quad: Unicode quadrant-block glyphs only (▘▝▖▗▚▞▛▜▙▟) — the
# family Terminus's console.font=ter-v32n (installer.nix) is built to
# cover well, instead of chafa's full symbol repertoire occasionally
# falling back to plain ASCII when a fancier glyph isn't confirmed safe.
# --color-space din99d: perceptually accurate colour quantization —
# closer to the real Kartoza palette than the faster default `rgb` mode.
chafa --size=20x --symbols quad --color-space din99d resources/kartoza-logo.png --format=symbols 2>/dev/null || true

cat <<EOF

  ${BOLD}gisnix${RESET} — a reproducible NixOS distribution for GIS workstations
  ${TEAL}─────────────────────────────────────────────────────────────────${RESET}

  ${TEAL}┌───┬────────────────────┬───────────────────┐${RESET}
  ${TEAL}│${RESET} ${ORANGE}→${RESET} ${TEAL}│${RESET} No network yet?    ${TEAL}│${RESET} ${BLUE}sudo nmtui${RESET}        ${TEAL}│${RESET}
  ${TEAL}│${RESET} ${ORANGE}→${RESET} ${TEAL}│${RESET} Ready to install?  ${TEAL}│${RESET} ${BLUE}sudo setup${RESET}        ${TEAL}│${RESET}
  ${TEAL}│${RESET} ${ORANGE}→${RESET} ${TEAL}│${RESET} Just want to look? ${TEAL}│${RESET} ${BLUE}sudo setup --mock${RESET} ${TEAL}│${RESET}
  ${TEAL}└───┴────────────────────┴───────────────────┘${RESET}

  Everything above needs sudo — you're logged in as nixos, not root.

  ${TEAL}─────────────────────────────────────────────────────────────────${RESET}
  ${ORANGE}→${RESET} ${BLUE}github.com/kartoza/gisnix${RESET}        ${ORANGE}→${RESET} ${BLUE}kartoza.com${RESET}
EOF
echo
