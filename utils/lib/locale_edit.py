#!/usr/bin/env python3
"""Get/set/clear the locale scalar fields in a host's config.nix.

Operates on the top-level attrset's simple `field = "value";` lines — the
locale preset and its three optional per-axis overrides:

    locale        the preset code (software/locale/locales.json)
    timeZone      clock override
    language      desktop-language override (a glibc locale)
    formatLocale  number/date/paper override (a glibc locale)

Only these four keys are touched, and only as top-level one-line string
assignments, so this stays a scalpel — it never reformats or reinterprets
the rest of config.nix. Used by `gisnix locale`.

    locale_edit.py <config.nix> get
    locale_edit.py <config.nix> set <field> <value>
    locale_edit.py <config.nix> clear <field>
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

FIELDS = ("locale", "timeZone", "language", "formatLocale")


def _line_re(field: str) -> re.Pattern[str]:
    # A top-level (two-space indent) assignment, commented or not.
    return re.compile(rf'^(?P<indent>  )(?P<hash>#\s*)?{re.escape(field)}\s*=\s*"[^"]*";.*$')


def read(text: str) -> dict[str, str]:
    """Every uncommented locale field currently set, field -> value."""
    out: dict[str, str] = {}
    for field in FIELDS:
        for line in text.splitlines():
            m = _line_re(field).match(line)
            if m and not m.group("hash"):
                out[field] = re.search(r'"([^"]*)"', line).group(1)
                break
    return out


def set_field(text: str, field: str, value: str) -> str:
    lines = text.splitlines()
    pat = _line_re(field)
    new_line = f'  {field} = "{value}";'
    for i, line in enumerate(lines):
        if pat.match(line):
            # Replace in place, dropping any comment marker, keeping a
            # trailing comment if one was present after the ';'.
            lines[i] = new_line
            return "\n".join(lines) + "\n"
    # No line at all: insert before the final closing brace.
    for i in range(len(lines) - 1, -1, -1):
        if lines[i].strip() == "}":
            lines.insert(i, new_line)
            return "\n".join(lines) + "\n"
    raise SystemExit(f"locale_edit: no closing '}}' found in config.nix to insert {field}")


def clear_field(text: str, field: str) -> str:
    pat = _line_re(field)
    kept = [ln for ln in text.splitlines() if not (pat.match(ln) and not pat.match(ln).group("hash"))]
    return "\n".join(kept) + "\n"


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    path = Path(argv[0])
    op = argv[1]
    text = path.read_text()

    if op == "get":
        for field, value in read(text).items():
            print(f"{field}\t{value}")
        return 0

    if op in ("set", "clear"):
        field = argv[2] if len(argv) > 2 else ""
        if field not in FIELDS:
            print(f"locale_edit: unknown field {field!r}; one of {', '.join(FIELDS)}", file=sys.stderr)
            return 2
        if op == "set":
            if len(argv) < 4:
                print("locale_edit: set needs a value", file=sys.stderr)
                return 2
            path.write_text(set_field(text, field, argv[3]))
        else:
            path.write_text(clear_field(text, field))
        return 0

    print(f"locale_edit: unknown op {op!r}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
