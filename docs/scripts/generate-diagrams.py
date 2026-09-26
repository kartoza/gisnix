#!/usr/bin/env python3
"""Render the hand-authored PlantUML diagrams to SVG and PNG.

Every diagram lives as a `.puml` source under docs/diagrams/ and includes
the shared Kartoza theme (docs/diagrams/_theme.puml). This renders each to

    docs/assets/diagrams/<name>.svg   — served in the HTML site
    docs/assets/diagrams/<name>.png   — embedded in the PDF export

with PlantUML (`-tsvg`) and then librsvg (`rsvg-convert`) for the PNG, so
the same source produces both. Nothing is hand-drawn and nothing is drawn
by an AI: the `.puml` is the source of truth and anyone can re-render it
with this script and the two tools it calls.

Run from the repo root after editing any diagram:

    python3 docs/scripts/generate-diagrams.py        # or: gisnix docs-diagrams

Skips a diagram whose source has not changed since its last render (a
digest stamp beside the output), so re-running is cheap. Missing tools are
reported and skipped rather than failing the whole run — the committed
SVG/PNG still ship.
"""

from __future__ import annotations

import hashlib
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
SRC_DIR = ROOT / "docs" / "diagrams"
OUT_DIR = ROOT / "docs" / "assets" / "diagrams"

#: Bump to force every diagram to re-render after a pipeline change.
RENDER_VERSION = "1"


def _digest(source_text: str) -> str:
    return hashlib.sha256((RENDER_VERSION + "\n" + source_text).encode()).hexdigest()[:16]


def main() -> int:
    plantuml = shutil.which("plantuml")
    rsvg = shutil.which("rsvg-convert")
    if plantuml is None:
        print("generate-diagrams: plantuml not found — nothing rendered", file=sys.stderr)
        return 0
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    pumls = sorted(p for p in SRC_DIR.glob("*.puml") if not p.name.startswith("_"))
    if not pumls:
        print("generate-diagrams: no diagrams under docs/diagrams/")
        return 0

    theme = (SRC_DIR / "_theme.puml").read_text() if (SRC_DIR / "_theme.puml").exists() else ""
    rendered = 0
    for puml in pumls:
        name = puml.stem
        svg = OUT_DIR / f"{name}.svg"
        png = OUT_DIR / f"{name}.png"
        stamp = OUT_DIR / f".{name}.sha"
        # Fold the theme into the digest so a theme edit re-renders everything.
        digest = _digest(theme + "\n" + puml.read_text())
        if svg.exists() and stamp.exists() and stamp.read_text().strip() == digest:
            continue

        # PlantUML writes <name>.svg into -o; run from SRC_DIR so the
        # `!include _theme.puml` resolves.
        subprocess.run(
            [plantuml, "-tsvg", "-o", str(OUT_DIR), puml.name],
            cwd=SRC_DIR,
            check=True,
        )
        if not svg.exists():
            print(f"generate-diagrams: {name}: plantuml produced no SVG", file=sys.stderr)
            continue

        if rsvg is not None:
            subprocess.run([rsvg, "--format=png", "-o", str(png), str(svg)], check=True)
        else:
            print(
                f"generate-diagrams: rsvg-convert not found — {name}.png not refreshed",
                file=sys.stderr,
            )

        stamp.write_text(digest)
        rendered += 1
        print(f"  {name}.puml -> {name}.svg" + ("" if rsvg is None else f" + {name}.png"))

    print(f"✓ {rendered} diagram(s) rendered, {len(pumls)} total")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
