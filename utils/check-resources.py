#!/usr/bin/env python3
"""Verify resources/ naming, and that every reference to it resolves.

Two things go wrong with a folder of binary assets, and neither is visible in
a diff.

The first is a broken reference. A nix file saying
`source = ../resources/foo.png` for a file that no longer exists fails only
when that host is evaluated, which may be days later on a different machine.
Renaming an asset and missing one reference is the obvious way in.

The second is drift in naming. resources/ had accumulated CamelCase,
UPPER_SNAKE and hyphenated names side by side — KartozaNixOS.png,
QGIS_wallpaper.png, kartoza-logo.svg — which makes a name impossible to guess
and invites the near-duplicate that then collides on rename.

Run from the repo root; also wired into pre-commit.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# lower-case, digits, hyphens and dots only. Dots are allowed because several
# assets legitimately carry a compound extension (qgis-background.gdm.png,
# nix-config-workflow.drawio.png).
NAME_RE = re.compile(r"^[a-z0-9]+(?:[-.][a-z0-9]+)*$")

REFERENCE_RE = re.compile(r"(?:\.\./)+resources/([A-Za-z0-9_./-]+)")


def tracked(*globs: str) -> list[str]:
    out = subprocess.run(
        ["git", "ls-files", *globs], cwd=ROOT, capture_output=True, text=True
    )
    return [line for line in out.stdout.split("\n") if line]


def main() -> int:
    problems: list[str] = []

    # 1. Every reference must resolve.
    for rel in tracked("*.nix", "*.sh"):
        path = ROOT / rel
        try:
            text = path.read_text()
        except (UnicodeDecodeError, OSError):
            continue
        for match in REFERENCE_RE.finditer(text):
            target = (path.parent / match.group(0)).resolve()
            if not target.exists():
                problems.append(f"{rel}: {match.group(0)} does not exist")

    # 2. Naming. Reported per file so a new asset is caught as it is added,
    #    rather than discovered during the next rename.
    for rel in tracked("resources/*"):
        name = Path(rel).name
        stem, _, ext = name.partition(".")
        if not NAME_RE.match(name):
            reason = []
            if any(c.isupper() for c in name):
                reason.append("upper case")
            if "_" in name:
                reason.append("underscore")
            problems.append(
                f"{rel}: {' and '.join(reason) or 'unexpected characters'}"
                " — resources are lower-case and hyphen-separated"
            )
        del stem, ext

    if problems:
        print("resources/ problems:")
        for p in problems:
            print(f"  ✗ {p}")
        return 1

    print(f"✓ resources/ naming consistent, all references resolve "
          f"({len(tracked('resources/*'))} assets)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
