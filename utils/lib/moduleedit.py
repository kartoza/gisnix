"""Add and remove packages in a `software/**/*.nix` module, and make bundles.

This is the dangerous half of `kz configure`. Editing `hosts/<name>/config.nix`
changes one machine; editing a module under `software/` changes **every host
whose bundles include it**, which today can be nine at once. So the rules are
stricter than they are for a host file:

  * an edit is located by PARSING, never by searching for a string. `firefox`
    appears in comments, in shell scripts embedded in indented strings, and in
    URLs; deleting the wrong one produces a module that still evaluates and
    quietly installs the wrong software
  * a package is only removed when it sits alone on its line. The repository
    writes one package per line everywhere, so this covers everything that
    exists — and where it does not hold, the editor refuses and says so rather
    than reaching into a line it does not understand
  * nothing is written unless the result passes `nix-instantiate --parse` AND
    reading it back yields exactly the package list that was asked for
  * every caller is told which hosts an edit reaches before it happens

The parsing is `bundleinfo`'s, not a second copy. That module was made
offset-preserving for this: it blanks comments and `with` headers rather than
deleting them, so a package's position in the analysed text is its position in
the real file.
"""

from __future__ import annotations

import json
import re
import subprocess
import shutil
import sys
import tempfile
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bundleinfo as I  # noqa: E402
import hostconfig as H  # noqa: E402


class Refused(Exception):
    """The edit was not attempted, and the reason is fit to show a person."""


@dataclass
class Entry:
    """One package in a module, and where it physically lives."""

    name: str
    line: int
    #: True when the line holds this package and nothing else but a comment.
    alone: bool


def _analysed(module: Path, text: str | None = None) -> tuple[str, str]:
    """(original text, text with comments and `with` headers blanked)."""
    raw = module.read_text() if text is None else text
    return raw, I.blank_with_headers(I.strip_comments(raw))


def _offsets(text: str) -> list[int]:
    """Character offset at which each line starts."""
    out, at = [0], 0
    for line in text.split("\n")[:-1]:
        at += len(line) + 1
        out.append(at)
    return out


def _line_of(offset: int, starts: list[int]) -> int:
    lo, hi = 0, len(starts) - 1
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if starts[mid] <= offset:
            lo = mid
        else:
            hi = mid - 1
    return lo


def entries(module: Path, text: str | None = None) -> list[Entry]:
    """Every package in the module, with the line it is on.

    Reads `text` when given rather than the file, so a sequence of edits can
    be composed in memory. Nothing may touch the module until the whole
    result has been validated — an editor that wrote as it went would leave a
    half-edited file behind on the first refusal.

    Only entries in a package-list attribute are returned. A `firefox` in a
    comment or inside an embedded shell script is not an entry, which is the
    whole reason this goes through the parser.
    """
    raw, masked = _analysed(module, text)
    starts = _offsets(raw)
    lines = raw.split("\n")

    found: list[Entry] = []
    for key in I.PACKAGE_KEYS:
        pattern = re.escape(key).replace(r"\*", r"[A-Za-z0-9_-]+")
        for match in re.finditer(pattern + r"\s*=", masked):
            span = I._statement_after(masked, match.end())
            for body, at in I._lists_in(span, match.end()):
                for name, offset in I._elements(body, at):
                    index = _line_of(offset, starts)
                    code, _ = H.split_comment(lines[index])
                    # `pkgs.grass` and a bare `grass` under `with pkgs` are
                    # the same entry, and the reader reports both as `grass`.
                    # Comparing the raw line against that name called the
                    # qualified form "not alone on its line" and refused to
                    # touch it — so every `pkgs.`-prefixed entry in the tree
                    # was uneditable.
                    written = I._strip_prefix(code.strip())
                    found.append(Entry(name, index, written == name))
    return found


def bundle_for(module: Path) -> dict | None:
    """The bundle that owns this module file, if any."""
    try:
        rel = module.resolve().relative_to((H.REPO_ROOT / "software").resolve())
    except ValueError:
        return None
    directory = str(rel.parent)
    return next((b for b in H.catalogue() if b["path"] == directory), None)


#: How an overlay attribute is defined, and whether that makes it ours.
#: `callPackage ./pkgs/...` and `inputs.<flake>.packages...` are packages this
#: repository provides and nowhere else does. `prev.signal-desktop.overrideAttrs`
#: is a patched nixpkgs package — still available if the entry goes, so it is
#: not locked.
_OURS = ("callPackage ./pkgs", "inputs.", "writeShellApplication", "writeShellScriptBin")

_OVERLAY_ATTR = re.compile(r"^    ([A-Za-z_][A-Za-z0-9_'-]*)\s*=", re.M)


@lru_cache(maxsize=1)
def overlay_packages() -> dict[str, str]:
    """Packages this flake DEFINES, name -> how.

    Derived from `overlays/default.nix` rather than listed, so a package added
    to the overlay tomorrow is protected without anyone remembering to record
    it here — the same rule the rest of this tooling follows.
    """
    overlay = H.REPO_ROOT / "overlays" / "default.nix"
    try:
        text = overlay.read_text()
    except OSError:
        return {}

    out: dict[str, str] = {}
    for match in _OVERLAY_ATTR.finditer(text):
        name = match.group(1)
        body = I._statement_after(text, match.end())
        if any(marker in body for marker in _OURS):
            kind = "built from overlays/pkgs/" if "callPackage ./pkgs" in body else (
                "provided by a flake input" if "inputs." in body else "a wrapper script"
            )
            out[name] = kind
    return out


#: Module-system attributes that sit at the same indentation as a `let`
#: binding but are not one. Nothing is named after them, so this is tidiness
#: rather than a fix — a lock explained by "the module builds `imports`"
#: would be nonsense to read.
_NOT_A_BINDING = {"imports", "config", "options", "meta", "environment", "programs"}


def locally_defined(module: Path, text: str | None = None) -> set[str]:
    """Names the module itself binds in a `let` block.

    `cosmic-ext-enroll`, `screenshot-satty` and `record-gif` are derivations
    written a few lines above the list that installs them. Deleting the list
    entry would leave the derivation behind, built by nothing and installed
    nowhere — a module that still evaluates and quietly does less.
    """
    raw = module.read_text() if text is None else text
    masked = I.blank_with_headers(I.strip_comments(raw))
    return {
        m.group(1)
        for m in re.finditer(r"^  ([A-Za-z_][A-Za-z0-9_'-]*)\s*=", masked, re.M)
        if m.group(1) not in _NOT_A_BINDING
    }


def required_package(module: Path, package: str) -> tuple[str, bool] | None:
    """Why this package's LIST ENTRY must not be deleted via edit mode, and
    whether that also means the package itself is mandatory.

    Returns `(reason, hard)` or `None`. `hard=True`: the package genuinely
    cannot be absent — bundle-level `required` protects a whole bundle from
    being dropped by a host, and this is the same idea one level down:
    `base` may not be removed from abyss, and `fish` may not be removed
    from `base`, because users/tim-headless.nix sets `shell = pkgs.fish`
    and a user whose login shell does not exist cannot log in.

    `hard=False`: the TEXT LINE is locked, not the package's presence.
    These are packages this repository defines itself (overlays/pkgs/, a
    flake input, a wrapper script) or builds in the module's own `let`
    block — deleting the literal entry does not free anything, the
    derivation stays, built by nothing and reaching no machine. What
    actually governs whether it installs is elsewhere: an option
    (`programs.<x>.enable`, `programs.<x>.apps.<id>.enable`) or, absent
    one, the bundle itself. Callers must not render this the same as
    `hard=True` — a package a host's config already keeps off by default
    is not "required" merely because kz configure cannot delete its
    source line.
    """
    bundle = bundle_for(module)
    if bundle is not None:
        stated = (bundle.get("requiredPackages") or {}).get(package)
        if stated:
            return (stated, True)

    # Packages this repository defines. Removing one from the list that
    # installs it does not free anything: the derivation stays, built by
    # nothing and reaching no machine. Whatever governs its PRESENCE —
    # an option if the module declares one, the bundle if it does not —
    # is the supported way to not have it; that stays available, which is
    # why this locks the entry rather than making the package mandatory.
    ours = overlay_packages().get(package)
    if ours:
        return (
            f"this flake defines {package} itself ({ours}); deleting this line "
            "would not remove it — use whatever option or bundle toggle "
            "actually governs it",
            False,
        )

    if package in locally_defined(module):
        return (
            f"{module.name} builds {package} in its own let block; deleting the "
            "entry would leave the derivation with nothing installing it",
            False,
        )
    return None


def hosts_using(bundle_name: str) -> list[str]:
    """Every host whose bundles resolve to include this one."""
    out = []
    for host in H.hosts():
        wanted = H.parse(H.path_for(host)).enabled
        if bundle_name in set(H.resolve(sorted(wanted))):
            out.append(host)
    return out


def remove(module: Path, package: str, text: str | None = None) -> str:
    """The module's text with `package` gone. Raises Refused if unsafe."""
    text = module.read_text() if text is None else text
    locked = required_package(module, package)
    if locked is not None:
        why, _hard = locked
        raise Refused(f"{package} cannot be removed from {module.name}: {why}")

    matching = [e for e in entries(module, text) if e.name == package]
    if not matching:
        raise Refused(f"{package} is not a package entry in {module.name}")
    if len(matching) > 1:
        raise Refused(
            f"{package} appears {len(matching)} times in {module.name}; "
            "remove it by hand so the intent is explicit"
        )
    entry = matching[0]
    if not entry.alone:
        raise Refused(
            f"{package} shares line {entry.line + 1} of {module.name} with "
            "other code. Removing it would mean rewriting that line, which "
            "this does not attempt"
        )

    lines = text.split("\n")
    del lines[entry.line]
    return "\n".join(lines)


def _first_list_line(module: Path, text: str) -> tuple[int, str] | None:
    """(line index of the list's opening bracket, that line's indent)."""
    _, masked = _analysed(module, text)
    starts = _offsets(text)
    lines = text.split("\n")
    for key in I.PACKAGE_KEYS:
        pattern = re.escape(key).replace(r"\*", r"[A-Za-z0-9_-]+")
        for match in re.finditer(pattern + r"\s*=", masked):
            span = I._statement_after(masked, match.end())
            for _body, at in I._lists_in(span, match.end()):
                index = _line_of(at, starts)
                line = lines[index]
                return index, " " * (len(line) - len(line.lstrip()))
    return None


def add(module: Path, package: str, text: str | None = None) -> str:
    """The module's text with `package` added to its first package list.

    Inserted in sorted position when the list is already sorted, and at the
    end when it is not — matching what is there rather than imposing an order
    on a list somebody grouped deliberately.
    """
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_'.-]*", package):
        raise Refused(f"{package!r} is not a plausible nixpkgs attribute name")

    text = module.read_text() if text is None else text
    present = entries(module, text)
    if any(e.name == package for e in present):
        raise Refused(f"{module.name} already installs {package}")

    usable = [e for e in present if e.alone]
    lines = text.split("\n")

    if not usable:
        # An empty list has no entry to copy an indent or a position from.
        # A bundle made by `g` starts exactly like this, so "no entries" must
        # mean "insert the first one", not "refuse".
        opened = _first_list_line(module, text)
        if opened is None:
            raise Refused(
                f"{module.name} has no package list to add to. Add "
                "`environment.systemPackages = with pkgs; [ ];` to it first."
            )
        at, indent = opened
        lines.insert(at + 1, f"{indent}  {package}")
        return "\n".join(lines)

    names = [e.name for e in usable]
    indent = " " * (len(lines[usable[0].line]) - len(lines[usable[0].line].lstrip()))

    if names == sorted(names):
        at = next(
            (e.line for e, n in zip(usable, names) if n > package),
            usable[-1].line + 1,
        )
    else:
        at = usable[-1].line + 1

    lines.insert(at, f"{indent}{package}")
    return "\n".join(lines)


def parses(text: str) -> tuple[bool, str]:
    """Does this evaluate as Nix? A syntax check only; builds nothing."""
    if shutil.which("nix-instantiate") is None:
        return True, "nix-instantiate is not on PATH; syntax was not checked"
    with tempfile.TemporaryDirectory() as tmp:
        candidate = Path(tmp) / "module.nix"
        candidate.write_text(text)
        proc = subprocess.run(
            ["nix-instantiate", "--parse", str(candidate)],
            capture_output=True,
            text=True,
        )
    return proc.returncode == 0, proc.stderr.strip()


def verify(module: Path, text: str, expected: set[str]) -> list[str]:
    """Read the rewritten module back and check it says what was asked."""
    problems: list[str] = []
    with tempfile.TemporaryDirectory() as tmp:
        candidate = Path(tmp) / module.name
        candidate.write_text(text)
        I.packages_in.cache_clear()
        got = set(I.packages_in(candidate)[0])
    I.packages_in.cache_clear()
    missing, extra = sorted(expected - got), sorted(got - expected)
    if missing:
        problems.append(f"not written: {', '.join(missing)}")
    if extra:
        problems.append(f"written but not asked for: {', '.join(extra)}")
    return problems


def apply(module: Path, text: str, expected: set[str]) -> None:
    """Validate and write, or raise Refused having changed nothing."""
    ok, message = parses(text)
    if not ok:
        raise Refused(f"the result does not parse as Nix:\n{message}")
    problems = verify(module, text, expected)
    if problems:
        raise Refused("the result does not say what was asked: " + "; ".join(problems))
    tmp = module.with_suffix(module.suffix + ".kz-new")
    tmp.write_text(text)
    tmp.replace(module)
    I.packages_in.cache_clear()
    I.counts.cache_clear()


def exists_in_nixpkgs(package: str) -> tuple[bool, str]:
    """Is this a real nixpkgs attribute? (answer, explanation).

    Adding a name that does not exist gives every host taking the bundle an
    evaluation error, discovered at the next rebuild rather than here. One
    `nix eval` costs a second or two against a warm cache, which is a good
    trade for not breaking nine machines on a typo.

    An unavailable nix is reported as "could not check" rather than as a
    refusal — the operator may be running this from a checkout on a machine
    without it.
    """
    if shutil.which("nix") is None:
        return True, "nix is not on PATH, so the name could not be checked"
    proc = subprocess.run(
        ["nix", "eval", "--raw", f"nixpkgs#{package}.name"],
        capture_output=True,
        text=True,
    )
    if proc.returncode == 0:
        return True, proc.stdout.strip()
    first = (proc.stderr.strip().split("\n") or [""])[0]
    return False, first or "nixpkgs has no such attribute"


def suggestions(prefix: str, limit: int = 12) -> list[str]:
    """Instant completions for a partly-typed package name.

    Drawn from `docs/references/software.json` — every package the fleet
    already installs — so the common case of "give this host what that host
    has" completes without touching nix at all. Anything outside that set is
    still addable; it just has to be typed in full and is checked against
    nixpkgs on submit.
    """
    prefix = prefix.strip().lower()
    if not prefix:
        return []
    try:
        index = json.loads(
            (H.REPO_ROOT / "docs" / "references" / "software.json").read_text()
        )
    except (OSError, ValueError):
        return []
    starts = sorted(n for n in index if n.lower().startswith(prefix))
    contains = sorted(n for n in index if prefix in n.lower() and n not in starts)
    return (starts + contains)[:limit]


def rendered(module: Path, expected: set[str]) -> str:
    """The module's text brought to exactly `expected`, entirely in memory.

    Composed by threading the text through each edit rather than by writing
    between them: a refusal partway must leave the file on disk untouched.
    """
    text = module.read_text()
    current = set(I.packages_in(module)[0])
    for package in sorted(current - expected):
        text = remove(module, package, text)
    for package in sorted(expected - current):
        text = add(module, package, text)
    return text


# ── making a new bundle ───────────────────────────────────────────────────

BUNDLE_NAME = re.compile(r"[a-z][a-z0-9-]*")

TEMPLATE = """# {title}
#
# {description}
{{ pkgs, ... }}:
{{
  environment.systemPackages = with pkgs; [
  ];
}}
"""


def create_bundle(path: str, description: str, implies: list[str] | None = None) -> Path:
    """Make a new bundle directory, its bundle.json and an empty module.

    `path` is relative to `software/`, so `desktop/audio` becomes the bundle
    `desktop-audio` — the name is derived, never typed, which is what keeps a
    bundle's name and its location the same fact.
    """
    parts = path.strip("/").split("/")
    for part in parts:
        if not BUNDLE_NAME.fullmatch(part):
            raise Refused(
                f"{part!r} is not a usable directory name: lowercase letters, "
                "digits and hyphens, starting with a letter"
            )

    directory = H.REPO_ROOT / "software" / "/".join(parts)
    if (directory / "bundle.json").exists():
        raise Refused(f"software/{path}/ is already a bundle")

    name = "-".join(parts)
    known = {b["name"] for b in H.catalogue()}
    for implied in implies or []:
        if implied not in known:
            raise Refused(f"{implied} is not a bundle, so {name} cannot imply it")

    # A bundle nested inside another implies its parent, the way every other
    # sub-bundle in the tree does. Without it a host taking only the child
    # would miss the group it belongs to.
    paths = {b["path"] for b in H.catalogue()}
    parent = H.parent_path("/".join(parts), paths)
    implied_names = list(implies or [])
    if parent:
        parent_name = parent.replace("/", "-")
        if parent_name not in implied_names:
            implied_names.append(parent_name)

    module = f"{parts[-1]}.nix"
    directory.mkdir(parents=True, exist_ok=True)
    (directory / module).write_text(
        TEMPLATE.format(title=H.B.title_for("/".join(parts)), description=description)
    )
    (directory / "bundle.json").write_text(
        json.dumps(
            {
                "name": name,
                "path": "/".join(parts),
                "description": description,
                "implies": implied_names,
                "modules": [module],
            },
            indent=2,
            ensure_ascii=True,
        )
        + "\n"
    )
    return directory
