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
# broad-Unicode-coverage variant. No color, and no Unicode block art for the
# logo: this session already found that Terminus (even the "v" charset) has
# no glyphs for the block-element range (U+2580-259F) chafa's default symbol
# renderer draws images with — that showed up first as garbled Textual
# widget borders, and chafa's own logo would have hit the exact same gap.
# `--symbols ascii -c none` is chafa's own documented recipe for
# guaranteed-safe old-school ASCII art; `--format=symbols` on top of that
# stops chafa auto-detecting Kitty/Sixel graphics support and emitting a
# binary protocol payload instead of text (see utils/shell-banner.sh's own
# comment on that — same tool, same gotcha).
#
# Safe to run any time: it only prints.
set -uo pipefail

clear
chafa --size=28x resources/kartoza-logo.png --format=symbols --symbols ascii -c none 2>/dev/null || true

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
