#!/usr/bin/env python3
"""A fuzzel panel (sized to ~80% of a 1920x1080-ish screen) listing every
keybind this tool knows about, grouped by the ## / ### heading it sits
under in the source markdown.

    keybind-cheatsheet docs/user/keyboard.md [more.md ...]

Deliberately NOT a from-scratch duplicate of the binding list: it parses
the actual markdown tables out of docs/user/keyboard.md (gisnix's own
documented source of truth for the mechanism it ships), baked in at build
time by the Nix module that wraps this script — so the cheatsheet can only
go stale the same way the docs themselves would, not as a second,
independently hand-maintained copy drifting away from a first.

Covers only what's IN those tables, which for gisnix's own docs means
home-row mods, bracket chords, clipboard holds, the navigation layer and
the herdr layer — aerc/obs and any other private, per-host layer have no
table in gisnix's own docs to parse (gisnix doesn't install aerc, and the
OBS brand is private — see obs-setup.py's own BRANDS comment for why).
Those show up here too if a private host also drops its own markdown
fragment, with the same table shape, into
/etc/xdg/keybind-cheatsheet/*.md — scanned in addition to whatever paths
are given on the command line.
"""

import glob
import os
import re
import subprocess
import sys

TABLE_ROW = re.compile(r"^\|(.+)\|\s*$")
SEPARATOR_ROW = re.compile(r"^\|[\s:|-]+\|\s*$")
HEADING = re.compile(r"^(#{1,3})\s+(.+)$")

EXTENSION_DIR = "/etc/xdg/keybind-cheatsheet"


def cells(line):
    return [c.strip() for c in line.strip("|").split("|")]


def parse_tables(markdown_text):
    """Yields (group, key, action) for every row of every GFM table in the
    text, `group` being whatever heading it last saw. A row's remaining
    columns (e.g. Tap/Hold) are joined with " / " into `action`."""
    lines = markdown_text.splitlines()
    group = ""
    i = 0
    while i < len(lines):
        line = lines[i]
        heading = HEADING.match(line)
        if heading:
            group = heading.group(2).strip()
            i += 1
            continue
        header_match = TABLE_ROW.match(line)
        if header_match and i + 1 < len(lines) and SEPARATOR_ROW.match(lines[i + 1]):
            i += 2  # skip header + separator row
            while i < len(lines):
                row_match = TABLE_ROW.match(lines[i])
                if not row_match:
                    break
                row = cells(row_match.group(0))
                if len(row) >= 2 and row[0]:
                    key = row[0].strip("`")
                    action = " / ".join(c for c in row[1:] if c)
                    yield group, key, action
                i += 1
            continue
        i += 1


def collect_entries(paths):
    entries = []
    for path in paths:
        try:
            with open(path, encoding="utf-8") as f:
                text = f.read()
        except OSError:
            continue
        entries.extend(parse_tables(text))
    if os.path.isdir(EXTENSION_DIR):
        for path in sorted(glob.glob(os.path.join(EXTENSION_DIR, "*.md"))):
            try:
                with open(path, encoding="utf-8") as f:
                    text = f.read()
            except OSError:
                continue
            entries.extend(parse_tables(text))
    return entries


def main():
    paths = sys.argv[1:]
    if not paths:
        sys.exit("usage: keybind-cheatsheet <markdown-file> [more.md ...]")

    entries = collect_entries(paths)
    if not entries:
        sys.exit("No keybind tables found in: " + ", ".join(paths))

    lines = "\n".join(f"{group:<22}{key:<14}→  {action}" for group, key, action in entries)

    # Fixed, not content-driven: the ask was a panel that fills ~80% of
    # the screen regardless of how much text is actually in it — fuzzel's
    # --width is a window size in character cells, not a content-fit
    # value, so a wide window with short lines just reads as generous
    # whitespace, which is the point. 170 cols / 28 rows is a rough
    # ~80% of a 1920x1080 screen at this font/line-height (fuzzel.ini);
    # tune alongside that file if the font size changes.
    subprocess.run(
        ["fuzzel", "--dmenu", "--width", "170", "--lines", "28", "--prompt", "keybinds ❯ "],
        input=lines,
        text=True,
        check=False,
    )


if __name__ == "__main__":
    main()
