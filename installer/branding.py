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


def render_logo_chafa(width: int = 60) -> str | None:
    """The logo rendered to terminal escape sequences via chafa, or None if
    chafa or the logo asset is unavailable (caller falls back to text)."""
    path = logo_path()
    if path is None:
        return None
    try:
        out = subprocess.run(
            ["chafa", f"--size={width}x", "--format=symbols", str(path)],
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        )
        return out.stdout
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return None
