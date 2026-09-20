"""What a bundle actually installs, for the `gisnix configure` preview pane.

`bundle.json` lists MODULES. An operator choosing between bundles wants to
know what lands on the machine — the packages — and a filename does not say.
`software/desktop/browsers/browsers.nix` could be anything; that it installs
Brave, Firefox, Chrome and Chromium is the fact worth seeing before ticking
the box.

WHY THIS READS THE SOURCE RATHER THAN EVALUATING IT

The exact answer is `nix eval` over the module set, which is what
`docs/scripts/generate-software-catalogue.py` does to build the catalogue
page. It takes minutes and gigabytes. A preview pane redraws on every cursor
movement, so it has a budget of milliseconds — a different problem needing a
different answer.

So this reads the Nix text and reports what it finds, and everything that
displays it says where the list came from. The failure mode is a package
arriving through a route the reader does not recognise and going unlisted:
under-reporting, never inventing. A module whose packages cannot be read is
shown as such rather than as empty, so "nothing listed" and "nothing there"
never look the same.
"""

from __future__ import annotations

import re
import sys
from functools import lru_cache
from pathlib import Path

# Bootstrap value, just to find hostconfig.py — always a sibling file in
# utils/lib/ regardless of where this tree is checked out or baked, so
# __file__-relative is safe here specifically.
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT / "utils" / "lib"))

import hostconfig as H  # noqa: E402

# Real value: GISNIX_ROOT (env var if set, same __file__ fallback otherwise)
# — see hostconfig.py's own comment for why this differs from a host's
# TARGET_ROOT. Every use below (software/, overlays/) is a bundle-catalogue
# reference, so GISNIX_ROOT is always the right one.
REPO_ROOT = H.GISNIX_ROOT

#: Attributes whose value is a list of packages.
PACKAGE_KEYS = (
    "environment.systemPackages",
    "home.packages",
    "users.users.*.packages",
)

#: Nix syntax and common local bindings that appear inside a package list but
#: are not packages. Without this the reader offers `with`, `lib`, `mkIf` and
#: `optionals` as things the machine will install.
NOISE = {
    "with", "pkgs", "lib", "config", "cfg", "optionals", "optional", "mkIf",
    "mkMerge", "mkBefore", "mkAfter", "if", "then", "else", "true", "false",
    "inherit", "let", "in", "map", "filter", "concatMap", "attrValues",
    "builtins", "toString", "elem", "hostConfig", "self", "super", "final",
    "prev", "system", "pkgs-unstable", "pkgs-master", "isLinux", "enable",
    # Builders and helpers. These appear inside a package list because they
    # PRODUCE the entry beside them — `(writeScriptBin "foo" …)` is a package
    # called foo, not a package called writeScriptBin. Reporting the builder
    # offers the reader something they could never install.
    "writeScriptBin", "writeShellScriptBin", "writeShellApplication",
    "writeTextFile", "writeText", "buildEnv", "symlinkJoin", "runCommand",
    "makeDesktopItem", "callPackage", "fetchFromGitHub", "fetchurl",
    "fetchgit", "makeWrapper", "wrapProgram", "stdenv", "mkDerivation",
    "override", "overrideAttrs", "linkFarm", "requireFile", "substituteAll",
    "hiPrio", "lowPrio", "plugins", "extraPkgs", "paths", "buildInputs",
}

_ENABLE_FLAT = re.compile(
    r"\b((?:programs|services|hardware|virtualisation)\.[A-Za-z0-9_.-]+)\.enable\s*=\s*true"
)
#: `programs.fish = { enable = true; … }` — the nested form. Missing it made
#: base/fish.nix, which is the only reason the fleet has a login shell, read
#: as a module that does nothing at all.
_ENABLE_BLOCK = re.compile(
    r"\b((?:programs|services|hardware|virtualisation)\.[A-Za-z0-9_.-]+)\s*=\s*\{"
)
_IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_'-]*(?:\.[A-Za-z0-9_'-]+)*")

#: `with pkgs;` puts a semicolon at bracket depth zero. A scanner looking for
#: "the semicolon that ends this assignment" stops dead on it and reads the
#: package list as empty — which is precisely what happened: browsers.nix,
#: whose entire content is four browsers, reported none. Dropping the `with`
#: header changes nothing about which identifiers appear inside the list.
_WITH = re.compile(r"\bwith\s+[A-Za-z0-9_.'-]+\s*;")


#: Nix's indented-string form. Modules embed whole shell scripts in these —
#: `writeScriptBin "battery-monitor" ''…''` — and every word of that script
#: looks like an identifier. Without removing them first, the reader offered
#: HOME, chmod, complete and KARTOZA_ALERT as things the machine installs.
_INDENTED = re.compile(r"''.*?''", re.S)


def strip_strings(text: str) -> str:
    """Remove indented-string bodies, keeping the rest of the module intact."""
    return _INDENTED.sub(" ", text)


def blank_with_headers(text: str) -> str:
    """Blank out `with pkgs;` headers, preserving every other offset."""
    return _WITH.sub(lambda m: " " * len(m.group(0)), text)


def strip_comments(text: str) -> str:
    """Drop `#` comments, leaving strings alone.

    A package list is full of trailing comments naming what each entry is
    for, and those comments name other packages. Reading them as entries
    would list software the module does not install.
    """
    out = []
    for line in text.split("\n"):
        i, in_string = 0, False
        while i < len(line):
            c = line[i]
            if in_string:
                if c == "\\":
                    i += 2
                    continue
                if c == '"':
                    in_string = False
            elif c == '"':
                in_string = True
            elif c == "#":
                # Blank the comment instead of truncating: every character
                # after it keeps its offset, which is what lets
                # moduleedit.py find a package in the real file rather than
                # in a rewritten copy of it.
                line = line[:i] + " " * (len(line) - i)
                break
            i += 1
        out.append(line)
    return "\n".join(out)


def _statement_after(text: str, at: int) -> str:
    """The rest of an assignment, from `at` to the `;` that closes it.

    Depth-counted rather than "up to the next semicolon", because a package
    list routinely contains one — `(with pkgs; [ … ])` is the common form, and
    stopping at that semicolon would read the list as empty.
    """
    depth = 0
    for i in range(at, len(text)):
        c = text[i]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == ";" and depth <= 0:
            return text[at:i]
    return text[at:]


#: Builders whose FIRST string argument is the name of the package they
#: produce. `(writeShellScriptBin "battery-monitor" ''…'')` installs
#: battery-monitor; naming the builder instead would offer the reader
#: something that does not exist.
NAMING_BUILDERS = {
    "writeScriptBin",
    "writeShellScriptBin",
    "writeShellApplication",
    "writeTextFile",
}


def _strip_prefix(word: str) -> str:
    for prefix in ("pkgs.", "pkgs-unstable.", "pkgs-master.", "lib."):
        if word.startswith(prefix):
            return word[len(prefix) :]
    return word


def _from_group(group: str) -> list[str]:
    """What a parenthesised entry in a package list actually installs.

    `(writeShellScriptBin "battery-monitor" ''…'')` installs
    battery-monitor — the builder's first string argument. Anything else
    contributes its first identifier that is not syntax: `(pkgs.wrapOBS {…})`
    is how OBS is installed here, and reporting nothing for it meant the most
    prominent application in desktop-multimedia was invisible, including to
    the filter. `(lib.hiPrio kartoza-cosmic-app-library-icon)` names the icon,
    not hiPrio.
    """
    words = group.split()
    if not words:
        return []
    if _strip_prefix(words[0]).split(".")[-1] in NAMING_BUILDERS and len(words) > 1:
        return [words[1]]
    for word in words:
        name = _strip_prefix(word)
        if name and name.split(".")[0] not in NOISE:
            return [name]
    return []


def _elements(body: str, base: int = 0) -> list[tuple[str, int]]:
    """The top-level entries of a Nix list.

    Reading identifiers out of the raw text does not work, and failed
    loudly: modules embed whole shell scripts in indented strings, so the
    reader offered HOME, chmod, CYAN and a row of underscores as packages.

    Walking the list instead — skipping anything nested inside brackets,
    braces, parentheses or a string — yields only what is actually an entry.
    A nested builder call contributes the name it builds, and anything else
    nested contributes nothing, which is the intended direction to fail in.
    """
    out: list[tuple[str, int]] = []
    i, depth = 0, 0
    token = ""
    token_at = 0
    group = ""

    def flush() -> None:
        nonlocal token
        if token:
            # `a.${x}.b` leaves a dot on each side of the removed
            # antiquotation, so collapse runs of them.
            name = _strip_prefix(re.sub(r"\.{2,}", ".", token))
            if depth == 0 and not name.startswith(".") and not name.endswith("."):
                out.append((name, base + token_at))
            token = ""

    while i < len(body):
        c = body[i]

        # Strings, in both of Nix's forms.
        if body.startswith("''", i):
            close = body.find("''", i + 2)
            i = len(body) if close == -1 else close + 2
            continue
        if c == '"':
            j = i + 1
            while j < len(body):
                if body[j] == "\\":
                    j += 2
                    continue
                if body[j] == '"':
                    break
                j += 1
            if depth > 0:
                group += " " + body[i + 1 : j]
            i = j + 1
            continue

        # `${system}` inside an attribute path. Skipping the antiquotation
        # and closing the token over it turns
        # `inputs.nvf.packages.${system}.default` into one readable name
        # instead of the two fragments `inputs.nvf.packages.` and `.default`.
        if body.startswith("${", i):
            close, nest = i + 2, 1
            while close < len(body) and nest:
                nest += (body[close] == "{") - (body[close] == "}")
                close += 1
            i = close
            continue

        if c in "([{":
            flush()
            depth += 1
            if depth == 1:
                group = ""
            i += 1
            continue
        if c in ")]}":
            flush()
            depth -= 1
            if depth == 0:
                out.extend((name, base + i) for name in _from_group(group))
                group = ""
            i += 1
            continue

        if c.isalnum() or c in "_-.'":
            if not token:
                token_at = i
            token += c
            if depth > 0:
                group += c
        else:
            flush()
            if depth > 0:
                group += " "
        i += 1

    flush()
    return out


def _lists_in(span: str, base: int = 0) -> list[tuple[str, int]]:
    """Every bracketed list in a span, so `a ++ optionals c [ … ]` is read whole."""
    found, depth, start = [], 0, None
    i = 0
    while i < len(span):
        # Do not mistake a bracket inside a string for list structure.
        if span.startswith("\'\'", i):
            close = span.find("\'\'", i + 2)
            i = len(span) if close == -1 else close + 2
            continue
        c = span[i]
        if c == "[":
            if depth == 0:
                start = i + 1
            depth += 1
        elif c == "]":
            depth -= 1
            if depth == 0 and start is not None:
                found.append((span[start:i], base + start))
                start = None
        i += 1
    return found


@lru_cache(maxsize=None)
def packages_in(module: Path) -> tuple[tuple[str, ...], tuple[str, ...], bool]:
    """(packages, enables, readable) for one module.

    `readable` is False when the module names no packages and enables nothing
    recognisable — it configures something in a way this reader does not
    follow. Displayed as "not read from source", never as "installs nothing".
    """
    try:
        text = blank_with_headers(strip_comments(module.read_text()))
    except OSError:
        return (), (), False

    packages: list[str] = []
    for key in PACKAGE_KEYS:
        pattern = re.escape(key).replace(r"\*", r"[A-Za-z0-9_-]+")
        for match in re.finditer(pattern + r"\s*=", text):
            span = _statement_after(text, match.end())
            for body, at in _lists_in(span, match.end()):
                for ident, _offset in _elements(body, at):
                    if not ident or ident.split(".")[0] in NOISE:
                        continue
                    if ident not in packages:
                        packages.append(ident)

    enables = []
    for name in _ENABLE_FLAT.findall(text):
        if name not in enables:
            enables.append(name)
    for match in _ENABLE_BLOCK.finditer(text):
        block = _statement_after(text, match.end() - 1)
        if re.search(r"\benable\s*=\s*true", block) and match.group(1) not in enables:
            enables.append(match.group(1))

    return tuple(packages), tuple(enables), bool(packages or enables)


def summarise(bundle: dict) -> dict:
    """Everything the preview pane shows about one bundle."""
    directory = REPO_ROOT / "software" / bundle["path"]
    modules = []
    for name in bundle.get("modules", []):
        packages, enables, readable = packages_in(directory / name)
        modules.append(
            {
                "name": name,
                "packages": list(packages),
                "enables": list(enables),
                "readable": readable,
            }
        )

    every = []
    for module in modules:
        for package in module["packages"]:
            if package not in every:
                every.append(package)

    return {
        "bundle": bundle,
        "modules": modules,
        "packages": every,
        "unread": [m["name"] for m in modules if not m["readable"]],
    }


@lru_cache(maxsize=1)
def counts() -> dict[str, int]:
    """name -> how many packages it names, for the list column."""
    return {b["name"]: len(summarise(b)["packages"]) for b in H.catalogue()}


@lru_cache(maxsize=None)
def first_comment(module: Path) -> str:
    """The module's own one-line description, from its header comment.

    `docs/scripts/generate-bundle-docs.py` grew this first, to fill the
    "What it is" column of the reference page. The preview pane needs exactly
    the same sentence for a module whose packages cannot be read, so the
    generator now calls this rather than keeping a second copy — the two
    drifting would mean the docs and the tool describing the same file
    differently.
    """
    try:
        text = module.read_text()
    except OSError:
        return ""

    collected: list[str] = []
    for raw in text.split("\n"):
        line = raw.strip()
        if not collected and not line:
            continue
        if not line.startswith("#"):
            break
        cleaned = line.lstrip("#").strip()
        # Skip decorative rules and SPDX headers.
        if not cleaned or set(cleaned) <= set("\u2500-=*_") or cleaned.startswith("SPDX"):
            if collected:
                break
            continue
        collected.append(cleaned)

    if not collected:
        return ""

    prose = " ".join(collected)
    for end in (". ", ".\n"):
        if end in prose:
            prose = prose.split(end)[0] + "."
            break
    if len(prose) > 120:
        prose = prose[:117].rsplit(" ", 1)[0] + "\u2026"
    return prose.rstrip(".")


def matches(bundle: dict, query: str) -> bool:
    """Does this bundle answer to a `/` filter?

    Matches its own name, any package it installs, or any of its module
    filenames. The package half is the point: typing "firefox" should answer
    "which bundle would install that?", which a name-only filter cannot.

    Module filenames are in there because some modules install through a
    wrapper the reader cannot name precisely — `obs.nix` reads as `wrapOBS` —
    and without the filename the most prominent application in
    desktop-multimedia would be unfindable.

    Lives here rather than in the TUI so it can be tested without a terminal.
    """
    query = query.strip().lower()
    if not query:
        return True
    if query in bundle["name"].lower():
        return True
    info = summarise(bundle)
    if any(query in package.lower() for package in info["packages"]):
        return True
    return any(query in module["name"].lower() for module in info["modules"])
