"""Read the software bundles, for anything on the Python side that needs them.

This is the counterpart to software/bundles.nix. Both read the same
bundle.json files; neither owns the data. A bundle is a directory under
software/ carrying a bundle.json that names it, describes it, says what it
implies and lists the modules belonging to it.

WHY THIS EXISTS

docs/scripts/taxonomy.py used to carry its own dictionary mapping directories
to display names — eighteen entries duplicating what bundle.json now states.
Within an hour of the bundle work it was already wrong: it still named
`software/desktop/reading` after that directory became `ebook-readers`, and
knew nothing of the base, peripherals, source-builds or AI bundles. That is
the whole argument for reading the definition rather than restating it.

Titles are DERIVED from the path rather than stored, so there is no third
field to keep in step: `services/cloud-and-sync` becomes "Services · Cloud &
sync". Only genuine acronyms need help, and those are listed once below.
"""

from __future__ import annotations

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
SOFTWARE = REPO_ROOT / "software"

# Words whose conventional capitalisation is not title-case.
_ACRONYMS = {
    "ai": "AI",
    "gis": "GIS",
    "tuis": "TUIs",
    "zfs": "ZFS",
    "vm": "VM",
    "dns": "DNS",
}

# Proper nouns, which keep their capital even mid-sentence.
_PROPER = {"kartoza": "Kartoza"}

# Top-level order for presentation: the layers as they stack, rather than
# alphabetically. base underpins everything; locale is a per-host detail.
_TOP_ORDER = ["base", "terminal", "desktop", "services", "security", "locale"]


def _titlecase(segment: str) -> str:
    """`cloud-and-sync` -> `Cloud & sync`, `gis` -> `GIS`."""
    if segment in _ACRONYMS:
        return _ACRONYMS[segment]
    words = segment.split("-")
    out = []
    for i, w in enumerate(words):
        if w == "and":
            out.append("&")
        elif w in _ACRONYMS:
            out.append(_ACRONYMS[w])
        elif i == 0:
            out.append(w.capitalize())
        else:
            out.append(w)
    return " ".join(out)


def _phrase(segment: str) -> str:
    """`ebook-readers` -> `ebook readers`, `gis` -> `GIS`, `kartoza-apps` -> `Kartoza apps`.

    For names used inside a sentence, where title case would read as shouting.
    """
    out = []
    for w in segment.split("-"):
        if w in _ACRONYMS:
            out.append(_ACRONYMS[w])
        elif w in _PROPER:
            out.append(_PROPER[w])
        elif w == "and":
            out.append("&")
        else:
            out.append(w)
    return " ".join(out)


def title_for(path: str) -> str:
    """`desktop/cloud-and-sync` -> `Desktop · Cloud & sync`."""
    return " · ".join(_titlecase(p) for p in path.split("/"))


def _sort_key(path: str) -> tuple:
    head = path.split("/")[0]
    rank = _TOP_ORDER.index(head) if head in _TOP_ORDER else len(_TOP_ORDER)
    # Depth before name, so a parent sorts above its own sub-bundles.
    return (rank, path.count("/"), path)


def load() -> list[dict]:
    """Every bundle, in presentation order.

    Each entry carries the bundle.json contents plus:
        title       display name derived from the path
        directory   Path to the bundle's directory
    """
    found = []
    for meta_path in SOFTWARE.rglob("bundle.json"):
        meta = json.loads(meta_path.read_text())
        meta["directory"] = meta_path.parent
        meta["title"] = title_for(meta["path"])
        found.append(meta)
    found.sort(key=lambda b: _sort_key(b["path"]))
    return found


def by_name() -> dict[str, dict]:
    return {b["name"]: b for b in load()}


def module_owner() -> dict[str, dict]:
    """Repo-relative module path -> the bundle that claims it."""
    owner = {}
    for b in load():
        for m in b.get("modules", []):
            owner[f"software/{b['path']}/{m}"] = b
    return owner


def resolve(names: list[str]) -> list[str]:
    """Expand bundle names through `implies`, transitively.

    Mirrors resolve in software/bundles.nix. Kept in step by both reading the
    same `implies` lists, not by one copying the other.
    """
    index = by_name()
    out: list[str] = []

    def step(name: str) -> None:
        if name in out:
            return
        bundle = index.get(name)
        if bundle is None:
            raise KeyError(f"unknown bundle {name!r}")
        out.append(name)
        for implied in bundle.get("implies", []):
            step(implied)

    for n in names:
        step(n)
    return out


def taxonomy_sentence() -> str:
    """The top-level groups and their children, as a prose clause.

    Derived rather than written down. The catalogue used to state this by
    hand — "`desktop/` (browsers, environments, games, GIS, Kartoza apps,
    multimedia, productivity, reading)" — and it was wrong within a day of the
    taxonomy work: `reading` had become `ebook-readers`, `cloud-and-sync` had
    split into three, and `security` had appeared as a new top level. None of
    that showed up as an error, because prose does not fail a check.
    """
    children: dict[str, list[str]] = {}
    for b in load():
        parts = b["path"].split("/")
        head = parts[0]
        children.setdefault(head, [])
        if len(parts) > 1:
            leaf = _phrase(parts[1])
            # Sub-sub-bundles (services/device/input) belong to their parent.
            if leaf not in children[head]:
                children[head].append(leaf)

    ordered = sorted(children, key=lambda h: _sort_key(h))
    clauses = []
    for head in ordered:
        kids = children[head]
        if kids:
            clauses.append(f"`{head}/` ({', '.join(sorted(kids, key=str.lower))})")
        else:
            clauses.append(f"`{head}/`")

    if len(clauses) > 1:
        return ", ".join(clauses[:-1]) + " and " + clauses[-1]
    return clauses[0] if clauses else ""
