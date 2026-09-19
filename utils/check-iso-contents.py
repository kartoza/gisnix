#!/usr/bin/env python3
"""Verify every file the ISO's own Nix modules reach for by relative path is
actually baked onto the ISO.

installer.nix's `isoImage.contents` lists a deliberate subset of this repo —
software/, overlays/, profiles/, users/, hosts/, templates/, deploy/, and a
handful of top-level files — copied onto the image at /gisnix/. A fresh
install run straight from the booted ISO evaluates flake.nix against THAT
copy, not the real checkout.

The failure this guards against is invisible from the checkout itself: a
module says `builtins.readFile ../../dotfiles/kitty.conf`, the file is right
there on disk, `nix-instantiate --parse` is happy, `check-bundles.py` is
happy — dotfiles/ simply never made it into isoImage.contents, so the exact
same reference is a missing-file evaluation error the moment it runs from the
ISO's own baked copy instead of a real checkout. `unlock-host.sh` was the one
that actually got hit; the same gap affects every dotfiles/ reference from a
bundle in DEFAULT_BUNDLES, which is most of them, because `base` includes
several.

This does not evaluate anything — no daemon required, same as
check-bundles.py. It parses installer.nix's isoImage.contents with a regex
(the block is a flat, uniform list of `{ source = ./X; target = "..."; }`
entries — a real parse would need a nix evaluator this repo cannot assume is
available), then walks every .nix file under each baked source looking for
relative-path references the same way check-bundles.py does, and checks each
one resolves to somewhere ALSO baked, not just somewhere real.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INSTALLER_NIX = ROOT / "installer.nix"

_SOURCE = re.compile(r"source\s*=\s*(\./[\w./-]+)\s*;")

_REF = re.compile(r"(\.{1,2}(?:/[\w.@+-]+)+)")


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return "\n".join(re.sub(r"#.*$", "", ln) for ln in text.split("\n"))


def baked_sources() -> list[str]:
    """Repo-relative paths installer.nix copies onto the ISO."""
    text = INSTALLER_NIX.read_text()
    block = re.search(r"isoImage\.contents\s*=\s*\[(.*?)\n  \];", text, re.S)
    if not block:
        raise SystemExit("check-iso-contents: could not find isoImage.contents in installer.nix")
    return [m.group(1)[2:] for m in _SOURCE.finditer(block.group(1))]


def is_baked(rel: Path, baked: list[str]) -> bool:
    rel_s = str(rel)
    return any(rel_s == b or rel_s.startswith(b + "/") for b in baked)


def main() -> int:
    baked = baked_sources()
    problems: list[str] = []

    files: list[Path] = []
    for b in baked:
        p = ROOT / b
        if p.is_dir():
            tracked = subprocess.run(
                ["git", "ls-files", "*.nix"], cwd=p, capture_output=True, text=True
            ).stdout.split()
            files.extend(p / t for t in tracked)
        elif p.suffix == ".nix" and p.is_file():
            files.append(p)

    for path in sorted(set(files)):
        rel = path.relative_to(ROOT)
        body = strip_comments(path.read_text(errors="ignore"))
        for match in _REF.finditer(body):
            ref = match.group(1)
            if body[match.end() : match.end() + 2] == "${" or ref.endswith((".", "..")):
                continue
            target = path.parent / ref
            if not target.exists():
                continue  # check-bundles.py's job — a real dangling reference
            target_rel = target.resolve().relative_to(ROOT)
            if not is_baked(target_rel, baked):
                problems.append(
                    f"{rel}: refers to {ref} ({target_rel}), which is not in "
                    "installer.nix's isoImage.contents — a fresh install run "
                    "from the booted ISO cannot find it"
                )

    if problems:
        print("iso-contents problems:", file=sys.stderr)
        for p in problems:
            print(f"  ✗ {p}", file=sys.stderr)
        return 1

    print(f"✓ {len(files)} baked .nix files, every relative reference is also baked")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
