#!/usr/bin/env python3
"""Derive a host-scoped mkdocs config for `gisnix docs-pdf`.

Writes a copy of mkdocs.yml whose nav holds only ONE host's pages — the
host page plus its companions (hosts/<host>-*.md: keyboard maps, storage
notes, and the like) — and whose PDF lands in
site/pdf/kartoza-nixos-<host>.pdf. Everything above `nav:` is carried
over verbatim (theme, plugins, markdown extensions), so the pages render
exactly as they do in the full handbook; only the page set and the
output name change. mkdocs-with-pdf composes the PDF from the nav, so
scoping the nav scopes the document.

Text surgery rather than a YAML round-trip on purpose: mkdocs.yml uses
`!!python/name:` tags that yaml.safe_load refuses, and `nav:` is the
file's final block, so "everything before nav, then our own nav" is both
simple and faithful.

Usage: build-host-pdf-config.py --host <host> --out <file>
The derived config must sit in the repo root (mkdocs resolves docs_dir
relative to the config file).
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    host = args.host

    host_page = ROOT / "docs" / "hosts" / f"{host}.md"
    if not host_page.exists():
        sys.exit(
            f"docs/hosts/{host}.md does not exist — run "
            "`python3 docs/scripts/generate-host-docs.py` first, and check "
            f"that {host!r} is a real host (see `nix eval .#all-hosts`)."
        )

    source = (ROOT / "mkdocs.yml").read_text()
    head, sep, _ = source.partition("\nnav:")
    if not sep:
        sys.exit("mkdocs.yml has no nav block — this script expects one to replace")

    head = head.replace(
        "output_path: pdf/kartoza-nixos.pdf",
        f"output_path: pdf/kartoza-nixos-{host}.pdf",
    )
    head = re.sub(
        r"cover_title: .*",
        f"cover_title: Kartoza NixOS — {host}",
        head,
        count=1,
    )
    head = re.sub(
        r"cover_subtitle: .*",
        f"cover_subtitle: The complete configuration of host “{host}” — "
        "hardware, services, installed software and keyboard maps.",
        head,
        count=1,
    )

    nav = [f"\nnav:\n  - {host}: hosts/{host}.md\n"]
    for companion in sorted((ROOT / "docs" / "hosts").glob(f"{host}-*.md")):
        title = companion.stem.replace("-", " ")
        nav.append(f"  - {title}: hosts/{companion.name}\n")

    args.out.write_text(head + "".join(nav))
    print(f"host-scoped mkdocs config for {host}: {args.out}")


if __name__ == "__main__":
    main()
