# SPDX-FileCopyrightText: Tim Sutton
# SPDX-License-Identifier: MIT
#
# brand.nix — the single source of truth for Kartoza's colours in this flake.
#
# PURE DATA. A palette, contrast-checked surface pairs, and semantic roles.
# No CSS, no code, no module system: consumers render it into whatever they
# need at build time. That is what lets the docs macros, the desktop theming
# and any future service theme read the same five numbers instead of three
# copies of them drifting apart.
#
# WHY IT IS A FILE AND NOT A MODULE
#
# The accent colours used to live inside profiles/kartoza.nix, in a `let`
# binding of a NixOS module. Nothing outside the module system could read
# them, so the documentation quoted hex codes by hand — which is the same
# failure the bundle registry exists to prevent, one layer up. Being a plain
# attrset means `nix eval --file brand.nix --json` answers in milliseconds,
# without evaluating a host.
#
# CONTRAST
#
# Every pairing under `surfaces` is checked against WCAG 2.2 AA by
# docs/scripts/brand.py, and the check runs in the docs build. The rule the
# palette must never break: light text on a dark surface, or dark text on a
# light surface — never light-on-light. `surfaces` bundles each background
# with the foreground that belongs on it so a consumer cannot pair them
# wrongly by accident.
rec {
  name = "Kartoza";

  # ── The accent palette ────────────────────────────────────────────────
  # These five are the brand. They came from profiles/kartoza.nix, which now
  # imports this file rather than defining them.
  colors = {
    highlight1 = "#DF9E2F"; # yellow/orange
    highlight2 = "#569FC6"; # blue
    highlight3 = "#8A8B8B"; # grey
    highlight4 = "#06969A"; # teal
    alert = "#CC0403"; # red
  };

  # ── Neutrals ──────────────────────────────────────────────────────────
  neutrals = {
    ink = "#1B1F23"; # body text on light
    paper = "#FFFFFF"; # light background
    night = "#12161A"; # dark background
    mist = "#F4F6F8"; # subtle light fill
  };

  # ── Contrast-safe pairings ────────────────────────────────────────────
  # background + the foreground that belongs on it. Checked, not asserted:
  # docs/scripts/brand.py computes every ratio here and the docs build fails
  # if one drops below AA.
  surfaces = {
    light = {
      bg = neutrals.paper;
      fg = neutrals.ink;
    };
    subtle = {
      bg = neutrals.mist;
      fg = neutrals.ink;
    };
    dark = {
      bg = neutrals.night;
      fg = neutrals.paper;
    };
    alert = {
      bg = colors.alert;
      fg = neutrals.paper;
    };
  };

  # ── Semantic roles ────────────────────────────────────────────────────
  # What a colour MEANS, so a consumer asks for the meaning rather than the
  # hex. Changing the palette then changes every consumer at once.
  roles = {
    primary = colors.highlight4; # teal — the Kartoza mark
    secondary = colors.highlight2; # blue
    accent = colors.highlight1; # yellow/orange
    muted = colors.highlight3; # grey
    danger = colors.alert; # red
  };
}
