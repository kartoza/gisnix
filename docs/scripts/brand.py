"""Read `brand.nix` and check its pairings against WCAG 2.2 AA.

`brand.nix` is pure data — no module system, no host — so this costs a
millisecond rather than an evaluation. That is the whole reason the palette
was moved out of `profiles/kartoza.nix`: colours nothing but nix could read
meant the documentation quoted hex codes by hand, and hand-quoted values are
the ones that go stale.

The contrast maths is the WCAG 2.2 definition: relative luminance with the
sRGB gamma expansion, then `(lighter + 0.05) / (darker + 0.05)`. AA wants 4.5
for body text and 3.0 for large text or UI components.
"""

from __future__ import annotations

import json
import subprocess
from functools import lru_cache
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
BRAND_NIX = REPO_ROOT / "brand.nix"

#: WCAG 2.2 AA thresholds.
AA_TEXT = 4.5
AA_LARGE = 3.0


@lru_cache(maxsize=1)
def load() -> dict:
    """The brand pack as a dict, or {} if nix cannot be reached.

    Returning empty rather than raising keeps `mkdocs serve` working outside
    the flake — the macros degrade to saying the palette is unavailable,
    which is better than a docs build that cannot start.
    """
    try:
        out = subprocess.run(
            ["nix-instantiate", "--eval", "--strict", "--json", str(BRAND_NIX)],
            capture_output=True,
            text=True,
            check=True,
            cwd=REPO_ROOT,
        )
    except (OSError, subprocess.CalledProcessError):
        return {}
    try:
        return json.loads(out.stdout)
    except ValueError:
        return {}


def _channel(value: float) -> float:
    """sRGB gamma expansion for one channel, per the WCAG definition."""
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def luminance(hex_colour: str) -> float:
    """Relative luminance of `#rrggbb`."""
    raw = hex_colour.lstrip("#")
    if len(raw) == 3:
        raw = "".join(c * 2 for c in raw)
    r, g, b = (int(raw[i : i + 2], 16) / 255 for i in (0, 2, 4))
    return 0.2126 * _channel(r) + 0.7152 * _channel(g) + 0.0722 * _channel(b)


def contrast(foreground: str, background: str) -> float:
    """Contrast ratio between two colours, 1.0 (identical) to 21.0 (black/white)."""
    a, b = luminance(foreground), luminance(background)
    lighter, darker = max(a, b), min(a, b)
    return (lighter + 0.05) / (darker + 0.05)


def surface_report() -> list[dict]:
    """Every declared surface pairing with its measured ratio and verdict."""
    brand = load()
    rows = []
    for name, pair in sorted((brand.get("surfaces") or {}).items()):
        ratio = contrast(pair["fg"], pair["bg"])
        rows.append(
            {
                "surface": name,
                "fg": pair["fg"],
                "bg": pair["bg"],
                "ratio": ratio,
                "text": ratio >= AA_TEXT,
                "large": ratio >= AA_LARGE,
            }
        )
    return rows


def failures() -> list[dict]:
    """Surfaces that do not reach AA for body text.

    Used by the docs build and by `utils/check-brand.py`, so a palette change
    that breaks a pairing fails on commit rather than in somebody's browser.
    """
    return [row for row in surface_report() if not row["text"]]
