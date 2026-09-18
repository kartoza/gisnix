#!/usr/bin/env python3
"""Fail when a locale module names something glibc does not support.

NixOS turns `i18n.defaultLocale = "en_ZA.UTF-8"` into the supportedLocales
entry `en_ZA.UTF-8/UTF-8` and hands it to glibc's locale generator. If the
name is not in glibc's SUPPORTED list the generator aborts, which fails the
build of every host using that locale — with an error about locale-gen rather
than about the module that named it.

`en_IN` is the trap: glibc spells it `en_IN/UTF-8`, with no charset suffix on
the name, while `en_ZA` and `en_GB` do carry one. Writing `en_IN.UTF-8` by
analogy looks right, passes every syntax check, and breaks bay.

Run from the repo root:  python3 utils/check-locales.py
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCALE_DIR = ROOT / "software" / "locale"

#: Locale names look like `xx_YY` with an optional `.CHARSET`.
NAME = re.compile(r'"([a-z]{2,3}_[A-Z]{2}(?:\.[A-Za-z0-9-]+)?)"')


def supported() -> set[str] | None:
    """Locale names glibc will generate, or None if the list is unavailable."""
    try:
        path = subprocess.run(
            ["nix-build", "--no-out-link", "<nixpkgs>", "-A", "glibcLocales"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        listing = Path(path) / "share" / "i18n" / "SUPPORTED"
    except (OSError, subprocess.CalledProcessError):
        # Fall back to whatever glibc is already in the store: this check is
        # about spelling, and the spellings do not move between releases.
        found = sorted(Path("/nix/store").glob("*glibc-locales-*/share/i18n/SUPPORTED"))
        if not found:
            return None
        listing = found[-1]

    try:
        text = listing.read_text()
    except OSError:
        return None
    names = set()
    for line in text.splitlines():
        line = line.strip().rstrip("\\").strip()
        if not line or line.startswith("#"):
            continue
        names.add(line.split("/")[0])
    return names


def main() -> int:
    names = supported()
    if not names:
        print("locales: glibc's SUPPORTED list not found — skipping", file=sys.stderr)
        return 0

    problems: list[str] = []
    for module in sorted(LOCALE_DIR.glob("*.nix")):
        for locale in sorted(set(NAME.findall(module.read_text()))):
            if locale in names:
                continue
            suggestion = ""
            base = locale.split(".")[0]
            if base in names:
                suggestion = f" — glibc spells it `{base}`, with no charset suffix"
            elif f"{base}.UTF-8" in names:
                suggestion = f" — glibc spells it `{base}.UTF-8`"
            problems.append(f"{module.name}: {locale!r} is not a glibc locale{suggestion}")

    if problems:
        print("locales: these names would fail the glibc-locales build:\n", file=sys.stderr)
        for problem in problems:
            print(f"  ✗ {problem}", file=sys.stderr)
        print(file=sys.stderr)
        return 1

    modules = len(list(LOCALE_DIR.glob("*.nix")))
    print(f"✓ every locale named in {modules} modules is one glibc supports")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
