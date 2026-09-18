#!/usr/bin/env python3
"""Add a host's page to the Hosts section of mkdocs.yml, alphabetically.

The page itself is generated from the registry by
docs/scripts/generate-host-docs.py, but mkdocs.yml lists its nav entries by
hand — so without this step a host gets a page that nothing ever links to.
Three hosts (atoll, bay, minimal) had exactly that: a generated page, absent
from the nav.

Idempotent: running it twice is a no-op.

Usage:  add-host-to-nav.py <name>...
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

MKDOCS = Path(__file__).resolve().parent.parent / "mkdocs.yml"


def sort_key(line: str) -> str:
    # "      - abyss keyboard: hosts/abyss-keyboard.md" -> "abyss keyboard"
    label = line.strip().lstrip("- ")
    return label.split(":")[0].strip().lower()


def main(names: list[str]) -> int:
    if not names:
        print("usage: add-host-to-nav.py <name>...", file=sys.stderr)
        return 2

    text = MKDOCS.read_text()
    lines = text.split("\n")

    try:
        start = next(i for i, l in enumerate(lines) if l.strip() == "- hosts/index.md")
    except StopIteration:
        print("add-host-to-nav: could not find the Hosts nav block in mkdocs.yml",
              file=sys.stderr)
        return 1

    end = start
    while end + 1 < len(lines) and "hosts/" in lines[end + 1]:
        end += 1

    indent = lines[start][: len(lines[start]) - len(lines[start].lstrip())]
    block = lines[start + 1 : end + 1]

    added = []
    for name in names:
        if re.search(rf"^\s*- .*: hosts/{re.escape(name)}\.md$", text, re.M):
            print(f"  {name} is already in the docs nav")
            continue
        block.append(f"{indent}- {name}: hosts/{name}.md")
        added.append(name)

    if not added:
        return 0

    block.sort(key=sort_key)
    lines[start + 1 : end + 1] = block
    MKDOCS.write_text("\n".join(lines))
    print(f"  added to the docs nav: {', '.join(added)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
