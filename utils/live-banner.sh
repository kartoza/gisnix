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
# broad-Unicode-coverage variant. The real console already renders the logo
# in full colour (chafa correctly detects it can't do Kitty/Sixel graphics
# there and falls back to symbols on its own) — --format=symbols just pins
# that choice explicitly rather than trusting auto-detection everywhere this
# might run.
#
# Safe to run any time: it only prints.
set -uo pipefail

clear
chafa --size=28x resources/kartoza-logo.png --format=symbols 2>/dev/null || true

cat <<'EOF'

  gisnix — a reproducible NixOS distribution for GIS workstations
  ─────────────────────────────────────────────────────────────────

  ┌───┬────────────────────┬───────────────────┐
  │ → │ No network yet?    │ sudo nmtui        │
  │ → │ Ready to install?  │ sudo setup        │
  │ → │ Just want to look? │ sudo setup --mock │
  └───┴────────────────────┴───────────────────┘

  Everything above needs sudo — you're logged in as nixos, not root.

  ─────────────────────────────────────────────────────────────────
  → github.com/kartoza/gisnix        → kartoza.com
EOF
echo
