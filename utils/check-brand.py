#!/usr/bin/env python3
"""Fail when a brand colour pairing drops below WCAG 2.2 AA.

`brand.nix` bundles each background with the foreground that belongs on it,
precisely so a consumer cannot pair them wrongly. That only helps if the
pairings themselves are checked — otherwise the file states a guarantee it
does not keep, which is worse than stating nothing.

The ratios are computed, not recorded. Change a hex code and this measures
the consequence on the next commit rather than leaving it to be noticed in
somebody's browser, or not noticed at all.

Run from the repo root:  python3 utils/check-brand.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "docs" / "scripts"))

import brand  # noqa: E402


def main() -> int:
    data = brand.load()
    if not data:
        print("brand: could not evaluate brand.nix — skipping", file=sys.stderr)
        return 0

    rows = brand.surface_report()
    bad = [r for r in rows if not r["text"]]

    if bad:
        print("brand: these pairings do not reach WCAG 2.2 AA:\n", file=sys.stderr)
        for row in bad:
            need = brand.AA_TEXT
            print(
                f"  ✗ {row['surface']}: {row['fg']} on {row['bg']} "
                f"is {row['ratio']:.2f}:1, needs {need}:1",
                file=sys.stderr,
            )
        print(
            "\n  Adjust the colours in brand.nix, or move the pairing out of"
            "\n  `surfaces` if it is not meant for body text.\n",
            file=sys.stderr,
        )
        return 1

    worst = min(rows, key=lambda r: r["ratio"])
    print(
        f"✓ {len(rows)} brand pairings meet WCAG 2.2 AA "
        f"(worst: {worst['surface']} at {worst['ratio']:.2f}:1)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
