"""The Kartoza palette, read from brand.nix so the installer never carries a
second copy of the hex codes to drift out of sync.

Falls back to a hardcoded copy (kept in sync by hand — see brand.nix) if nix
cannot be reached, mirroring docs/scripts/brand.py's own graceful
degradation. That should not happen on a NixOS live ISO (nix-instantiate is
always present), but a hard failure here would take down the whole wizard
over a cosmetic lookup, which is a bad trade.
"""

from __future__ import annotations

import json
import subprocess
from functools import lru_cache
from pathlib import Path

#: Kept in sync with brand.nix by hand; only used if nix-instantiate fails.
_FALLBACK = {
    "name": "Kartoza",
    "colors": {
        "highlight1": "#DF9E2F",
        "highlight2": "#569FC6",
        "highlight3": "#8A8B8B",
        "highlight4": "#06969A",
        "alert": "#CC0403",
    },
    "neutrals": {
        "ink": "#1B1F23",
        "paper": "#FFFFFF",
        "night": "#12161A",
        "mist": "#F4F6F8",
    },
    "roles": {
        "primary": "#06969A",
        "secondary": "#569FC6",
        "accent": "#DF9E2F",
        "muted": "#8A8B8B",
        "danger": "#CC0403",
    },
}


def find_gisnix_root() -> Path | None:
    """Locate the gisnix flake checkout baked onto the live ISO.

    Checked in order: $GISNIX_ROOT, then walking up from this file looking
    for a directory that has both flake.nix and brand.nix (true when running
    from a source checkout during development), then the ISO's well-known
    mount point.
    """
    import os

    env = os.environ.get("GISNIX_ROOT")
    if env and (Path(env) / "brand.nix").exists():
        return Path(env)

    here = Path(__file__).resolve().parent
    for candidate in [here, *here.parents]:
        if (candidate / "flake.nix").exists() and (candidate / "brand.nix").exists():
            return candidate

    for well_known in (Path("/etc/gisnix"), Path("/iso/gisnix"), Path("/home/gisnix")):
        if (well_known / "brand.nix").exists():
            return well_known

    return None


@lru_cache(maxsize=1)
def load() -> dict:
    root = find_gisnix_root()
    if root is None:
        return _FALLBACK
    try:
        out = subprocess.run(
            ["nix-instantiate", "--eval", "--strict", "--json", str(root / "brand.nix")],
            capture_output=True,
            text=True,
            check=True,
            timeout=15,
        )
        return json.loads(out.stdout)
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired, ValueError):
        return _FALLBACK


def textual_css_vars() -> str:
    """Render the palette as Textual CSS custom-ish constants (a `$var:` block
    is not native to Textual CSS, so this returns literal color values keyed
    by role for f-string interpolation into the App's CSS instead)."""
    brand = load()
    roles = brand.get("roles", _FALLBACK["roles"])
    neutrals = brand.get("neutrals", _FALLBACK["neutrals"])
    return {
        "primary": roles.get("primary", _FALLBACK["roles"]["primary"]),
        "secondary": roles.get("secondary", _FALLBACK["roles"]["secondary"]),
        "accent": roles.get("accent", _FALLBACK["roles"]["accent"]),
        "muted": roles.get("muted", _FALLBACK["roles"]["muted"]),
        "danger": roles.get("danger", _FALLBACK["roles"]["danger"]),
        "ink": neutrals.get("ink", _FALLBACK["neutrals"]["ink"]),
        "paper": neutrals.get("paper", _FALLBACK["neutrals"]["paper"]),
        "night": neutrals.get("night", _FALLBACK["neutrals"]["night"]),
        "mist": neutrals.get("mist", _FALLBACK["neutrals"]["mist"]),
    }


def logo_path() -> Path | None:
    """resources/kartoza-logo.png, for rendering with chafa on the welcome
    screen — no hand-drawn ASCII substitute; the real mark or nothing."""
    root = find_gisnix_root()
    if root is None:
        return None
    candidate = root / "resources" / "kartoza-logo.png"
    return candidate if candidate.exists() else None


#: --symbols quad restricts chafa to the Unicode quadrant-block glyphs
#: (▘▝▖▗▚▞▛▜▙▟ etc.) instead of its full "beautiful character art" symbol
#: repertoire, which pulls in braille/geometric/alpha glyphs the console's
#: Terminus font (installer.nix's ter-v32n) has no guarantee of carrying —
#: the "ugly ascii" chafa falls back to when it can't confirm a fancier
#: glyph is safe. Quadrant blocks are the same glyph family Terminus is
#: built to cover well. --color-space din99d is chafa's perceptually
#: accurate quantization mode (vs. the faster-but-cruder default `rgb`) —
#: worth the extra CPU for a logo rendered once per process, not per frame.
_CHAFA_SYMBOL_ARGS = ["--symbols", "quad", "--color-space", "din99d"]

#: Columns for the small per-screen corner badge (base.py's title row) —
#: distinct from the full-size welcome-banner render, which passes its own
#: width. 6 columns renders 3 rows at chafa's quad-block aspect — small
#: enough to sit beside the step-count badge without growing the title
#: row (and eating into every screen's body space) any more than needed.
CORNER_BADGE_WIDTH = 6


def render_logo_chafa(width: int = 60) -> str | None:
    """The logo rendered to terminal escape sequences via chafa, or None if
    chafa or the logo asset is unavailable (caller falls back to text)."""
    path = logo_path()
    if path is None:
        return None
    try:
        out = subprocess.run(
            ["chafa", f"--size={width}x", *_CHAFA_SYMBOL_ARGS, "--format=symbols", str(path)],
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        )
        # Chafa hides/shows the cursor around its own output (harmless when
        # printed straight to a real terminal, but these are cursor-visibility
        # CSI sequences, not SGR/color codes — Rich's Text.from_ansi (used to
        # embed this in the corner badge) only understands SGR, so strip them
        # rather than risk them rendering as literal garbage in a widget.
        return out.stdout.replace("\x1b[?25l", "").replace("\x1b[?25h", "")
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return None


@lru_cache(maxsize=1)
def render_corner_badge() -> str | None:
    """The small logo badge every wizard screen's title row carries —
    cached, since it's identical on every screen and every screen
    construction would otherwise re-shell out to chafa for it."""
    return render_logo_chafa(width=CORNER_BADGE_WIDTH)


@lru_cache(maxsize=1)
def corner_badge_rows() -> int:
    """How many text rows render_corner_badge()'s output actually needs —
    base.py sizes the whole title row to this rather than guessing, so a
    change to CORNER_BADGE_WIDTH (or chafa's own aspect handling) can't
    silently clip the badge. Falls back to 1 (a bare single-line title
    bar, no badge shown) if chafa/the logo aren't available."""
    ansi = render_corner_badge()
    if not ansi:
        return 1
    return max(len(ansi.rstrip("\n").splitlines()), 1)
