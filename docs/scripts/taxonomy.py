"""Group packages by the taxonomy the flake itself uses.

WHY THIS REPLACED A KEYWORD TABLE

generate-host-docs.py used to carry ~200 lines of hand-maintained
`PACKAGE_CATEGORIES` — a dict mapping package names to invented buckets like
"Development · Tooling" and "System · Theming & fonts". It was a second source
of truth for how software is organised, and it had drifted exactly as you would
expect: it still had categories for KDE Plasma, GNOME and XFCE environments,
none of which this fleet runs, while having no category at all for `services/`
or `locale/`, which it does.

The flake already states the taxonomy, in the shape of `software/`:

    terminal/   shells · tools · tuis
    desktop/    browsers · environments · games · gis · kartoza-apps ·
                multimedia · productivity · reading
    services/   cloud-and-sync · device · system · virtualisation
    locale/     one module per country

So a package's category is simply *where it is declared*. That cannot drift
from the flake, because it is read out of the flake.

HOW IT WORKS, AND WHAT IT CANNOT DO

Every `environment.systemPackages` / `home.packages` list under software/,
profiles/, hosts/, users/ and overlays/ is scanned, and each package name is
attributed to the file that declares it.

About half of what a host installs is not declared by us at all: NixOS modules
contribute accountsservice, at-spi2-core, bluez and hundreds more as a side
effect of enabling a service or a desktop. Those genuinely have no place in our
taxonomy, and are reported honestly under "Provisioned by NixOS modules"
rather than being guessed into a bucket by keyword.

This is a textual scan, not an evaluation. A package assembled by string
interpolation or pulled from a `let` binding will not be matched, and will fall
into the indirect group. That is a soft failure — the package still appears in
the catalogue, just in the honest bucket.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent

sys.path.insert(0, str(REPO_ROOT / "utils" / "lib"))

import bundleinfo  # noqa: E402

# Directories that can declare packages. Deliberately excludes .vscode/,
# legacy/ and result/ — the first contains editor settings that happen to
# mention package names, the others are not part of the live configuration.
_SCAN_ROOTS = ("software", "profiles", "hosts", "users", "overlays")

_ATTR_RE = re.compile(r"(?:environment\.systemPackages|home\.packages)\s*=\s*")

# Matches both `with pkgs; [ foo ]` and `[ pkgs.foo ]` / `[ unstable.foo ]`.
_TOKEN_RE = re.compile(
    r"(?:(?:pkgs|unstable|masterPkgs|final|prev)\.)?(?<![\w\-])([a-zA-Z][\w.\-]*)"
)

# Nix keywords and binding names that appear inside package lists but are not
# packages.
_SKIP = {
    "with", "pkgs", "lib", "inherit", "if", "then", "else", "true", "false",
    "null", "unstable", "config", "final", "prev", "mkIf", "mkAfter",
    "mkBefore", "optionals", "optional", "map", "builtins", "import", "let",
    "in", "or", "masterPkgs", "system", "mkForce", "mkDefault",
}

# Display names and ordering come from the bundle definitions — the
# bundle.json beside each set of modules — not from a table here.
#
# There used to be a table here: eighteen entries mapping directory to label.
# It was wrong within an hour of the bundles landing, still naming
# software/desktop/reading after that directory became ebook-readers, and
# blind to the base, peripherals, source-builds and AI bundles added at the
# same time. Reading the definition removes the possibility.
import bundles as _bundles  # noqa: E402

_LABELS: dict[str, str] = {f"software/{b['path']}": b["title"] for b in _bundles.load()}

_ORDER = [b["title"] for b in _bundles.load()] + [
    "Declared in a profile",
    "Declared by a host",
    "Declared for a user",
    "Custom packages & overlays",
    "Provisioned by NixOS modules",
]

_PROFILE = "Declared in a profile"
_HOST = "Declared by a host"
_USER = "Declared for a user"
_OVERLAY = "Custom packages & overlays"
_INDIRECT = "Provisioned by NixOS modules"


def _rhs(text: str, start: int) -> str:
    """Return the whole right-hand side of an assignment, from `start` to its
    terminating semicolon at nesting depth zero.

    Taking only the first `[...]` was not enough. Package lists here are
    routinely built by concatenation:

        environment.systemPackages = [ a ] ++ lib.optionals (!slim) [ b c ];

    and grabbing the first bracket group silently dropped everything after the
    `++` — which is how `baboon` and `cheetah` came to be reported as
    "provisioned by NixOS modules" when the Kartoza profile declares them
    explicitly. Nested brackets are honoured too, since a non-greedy regex
    would stop at the first `]`.
    """
    # `with pkgs; [ … ]` puts a semicolon at depth zero BEFORE the list, so
    # scanning for the terminating one has to step over the `with` header
    # first or it stops immediately and finds nothing.
    header = re.match(r"\s*with\s+[^;]+;", text[start:])
    if header:
        start += header.end()

    depth = 0
    for i in range(start, len(text)):
        ch = text[i]
        if ch in "[({":
            depth += 1
        elif ch in "])}":
            depth -= 1
            if depth < 0:
                return text[start:i]
        elif ch == ";" and depth == 0:
            return text[start:i]
    return text[start:]


def _category_for_path(path: str) -> str:
    for prefix, label in _LABELS.items():
        if path.startswith(prefix + "/") or path == prefix + ".nix":
            return label
    if path.startswith("software/locale"):
        return "Locale"
    if path.startswith("profiles/"):
        return _PROFILE
    if path.startswith("hosts/"):
        return _HOST
    if path.startswith("users/"):
        return _USER
    if path.startswith("overlays/"):
        return _OVERLAY
    return _INDIRECT


_declaration_cache: dict[str, str] | None = None


def declaration_map() -> dict[str, str]:
    """package name -> category label, from where it is declared.

    The reading is `utils/lib/bundleinfo.py`'s, not a second implementation.
    This module used to scan the whole right-hand side of an assignment for
    anything that looked like an identifier, which attributed 228 things that
    are not packages — `HOME`, `CYAN`, `Ctrl`, `KARTOZA_ALERT`, `Alt` — every
    one of them a word from a shell script embedded in an indented string.

    It also got real packages wrong. `software/desktop/games/retroarch.nix`
    installs one derivation, `retroarch`, with `cores = with libretro; [ …
    fuse ]` nested inside it. Scanning the text found `fuse` and filed the
    FUSE filesystem library under "Desktop · Games". The shared reader walks
    list elements and steps over nested groups, so it does not.
    """
    global _declaration_cache
    if _declaration_cache is not None:
        return _declaration_cache

    found: dict[str, str] = {}
    for nix_file in sorted(REPO_ROOT.rglob("*.nix")):
        rel = nix_file.relative_to(REPO_ROOT).as_posix()
        if rel.split("/")[0] not in _SCAN_ROOTS:
            continue
        category = _category_for_path(rel)
        for token in bundleinfo.packages_in(nix_file)[0]:
            if token in _SKIP:
                continue
            # A package declared in software/ wins over the same name
            # mentioned in a host or profile: software/ is where the
            # taxonomy lives, and the other is usually an override.
            if token in found and found[token] in _LABELS.values():
                continue
            found[token] = category

    _declaration_cache = found
    return found


def categorise_packages(packages: list[str]) -> dict[str, list[str]]:
    """Group package names by where the flake declares them.

    Returns categories in the taxonomy's own order, each with a sorted,
    de-duplicated package list. Empty categories are omitted.
    """
    declared = declaration_map()
    buckets: dict[str, list[str]] = {}
    for name in sorted(set(packages), key=str.lower):
        buckets.setdefault(declared.get(name, _INDIRECT), []).append(name)

    ordered: dict[str, list[str]] = {}
    for label in _ORDER:
        if buckets.get(label):
            ordered[label] = buckets[label]
    # Anything with a label not in _ORDER would be a bug, but surface it
    # rather than dropping packages on the floor.
    for label, names in buckets.items():
        if label not in ordered:
            ordered[label] = names
    return ordered


def category_note(label: str) -> str:
    """One line explaining a category, for the catalogue page.

    For a bundle this is its own description, so the docs say exactly what the
    configuration says. The remaining categories are not bundles — they
    describe where a package came from when no bundle claims it.
    """
    if label == _INDIRECT:
        return (
            "Not declared by this flake. These arrive as a side effect of "
            "enabling a NixOS service or desktop module, so they have no place "
            "in the `software/` taxonomy."
        )
    if label == _PROFILE:
        return "Declared directly in a `profiles/` module rather than under `software/`."
    if label == _HOST:
        return "Declared by a single host, in `hosts/<name>/`."
    if label == _USER:
        return "Declared for a specific user, in `users/`."
    if label == _OVERLAY:
        return "Built by this repo in `overlays/`."

    for bundle in _bundles.load():
        if bundle["title"] == label:
            return bundle["description"]
    return ""
