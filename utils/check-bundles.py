#!/usr/bin/env python3
"""Verify every software module is accounted for by a bundle.

A bundle is a directory under software/ carrying a bundle.json that lists the
modules belonging to it. The failure this guards against is quiet: add a new
.nix file to software/desktop/productivity/, forget to list it, and it is
simply never installed anywhere. Nothing errors, nothing warns, and the
package is missing on every host until somebody notices by hand.

So every .nix file in a bundle directory must be either:

  * in "modules"   — part of the bundle, installed by hosts that take it, or
  * in "unclaimed" — present but deliberately not installed

"unclaimed" is a real state, not a dumping ground: the tree carries modules
kept for reference, and listing them says "we know" rather than leaving it
ambiguous.

A bundle may also declare `"selection": "one-of"`, meaning its modules are
ALTERNATIVES rather than companions — software/locale/ is the clear case: a
machine has one locale, not eight. Those bundles are never imported wholesale;
the host names the member it wants.

Also checks that every claimed module IS a NixOS module, that every `implies`
names a bundle that exists, and that every relative path in the repo resolves.

The "is it actually a module" check has caught two different things already: a
package derivation filed as a module (`{ appimageTools, fetchurl }`, which the
module system's `outputs` argument breaks on) and helper functions meant to be
imported with explicit arguments (`{ pkgs, lib }: qgis: …`). Both look like
modules at a glance and fail only when something imports them.

That last one earns its place. Moving a module is routine, and a module that
imports a sibling with `./other.nix` breaks silently when it moves and the
sibling does not. Nix only complains when a host using it is evaluated — and
if nothing imports the module yet, not even then. Two moves in this refactor
introduced exactly that, and one of them broke evaluation for six hosts.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOFTWARE = ROOT / "software"


def main() -> int:
    bundles = {}
    for meta_path in sorted(SOFTWARE.rglob("bundle.json")):
        meta = json.loads(meta_path.read_text())
        bundles[meta["name"]] = (meta_path.parent, meta)

    problems: list[str] = []

    for name, (directory, meta) in sorted(bundles.items()):
        rel = directory.relative_to(ROOT)

        if meta.get("path") != str(rel.relative_to("software")):
            problems.append(
                f"{rel}/bundle.json: path is {meta.get('path')!r}, "
                f"but the file sits in {rel.relative_to('software')}"
            )

        claimed = set(meta.get("modules", [])) | set(meta.get("unclaimed", []))
        present = {p.name for p in directory.glob("*.nix") if p.name != "default.nix"}

        for missing in sorted(present - claimed):
            problems.append(
                f"{rel}/{missing}: no bundle claims this module — add it to "
                f'"modules" to install it, or to "unclaimed" to say so deliberately'
            )
        for ghost in sorted(claimed - present):
            problems.append(f"{rel}/bundle.json lists {ghost}, which does not exist")

        for implied in meta.get("implies", []):
            if implied not in bundles:
                problems.append(
                    f"{rel}/bundle.json implies {implied!r}, which is not a bundle"
                )

    for name, (directory, meta) in sorted(bundles.items()):
        sel = meta.get("selection", "all")
        if sel not in ("all", "one-of"):
            problems.append(
                f"{directory.relative_to(ROOT)}/bundle.json: selection is {sel!r}, "
                'expected "all" or "one-of"'
            )

    # A one-of group has to say how its member is chosen, and if that is a
    # host key, its module names must match what profiles/bundles.nix will
    # look for.
    #
    # Both halves exist because both have already gone wrong. bundles.nix read
    # `b.choiceKey` off every one-of group, which threw "attribute 'choiceKey'
    # missing" on boot-themes and broke a rebuild — while the Python quietly
    # skipped that group, so nothing here noticed. And a value the menu offers
    # that resolves to no file is an eval error at rebuild time, which is the
    # worst possible moment to find out.
    for name, (directory, meta) in sorted(bundles.items()):
        if meta.get("selection") != "one-of":
            continue
        rel = directory.relative_to(ROOT)
        key = meta.get("choiceKey")
        if not key:
            if not meta.get("choiceSelectedBy"):
                problems.append(
                    f"{rel}/bundle.json: selection is one-of but it declares "
                    'neither "choiceKey" (a config.nix key naming the member) '
                    'nor "choiceSelectedBy" (prose saying how else the member '
                    "is chosen). One of the two is required, so a group is "
                    "never silently unreachable"
                )
            continue
        prefix = meta.get("modulePrefix", key)
        members = [
            mod
            for mod in meta.get("modules", [])
            if mod.startswith(prefix + "-") and mod.endswith(".nix")
        ]
        values = [mod[len(prefix) + 1 : -len(".nix")] for mod in members]
        if not members:
            problems.append(
                f"{rel}/bundle.json: has choiceKey {key!r} but no module named "
                f"{prefix}-<value>.nix, so the group offers nothing"
            )

        # A module that is not itself a member is allowed, but only as a PART
        # of one: boot-theme-kartoza.nix imports the Plymouth and GRUB halves,
        # because a splash and a menu that disagree read as a fault. What is
        # not allowed is a module reachable from neither — it would sit in the
        # bundle installing nothing, which is the state check-bundles exists
        # to make impossible.
        imported = set()
        for member in members:
            text = (directory / member).read_text() if (directory / member).exists() else ""
            imported |= {m.strip() for m in re.findall(r"\./([A-Za-z0-9._-]+\.nix)", text)}
        for mod in meta.get("modules", []):
            if mod in members or mod in imported:
                continue
            problems.append(
                f"{rel}/bundle.json: {mod} is neither a member "
                f"({prefix}-<value>.nix) nor imported by one, so nothing can "
                f"ever install it"
            )

        default = meta.get("choiceDefault")
        if default is not None and default not in values:
            problems.append(
                f"{rel}/bundle.json: choiceDefault {default!r} is not one of "
                f"{values}"
            )

    # A claimed module must be usable as a NixOS module: a function whose
    # argument set ends in `...`, so the module system can pass whatever it
    # likes. A fixed argument list means the file is a package derivation or a
    # helper, and importing it fails with "called with unexpected argument".
    for name, (directory, meta) in sorted(bundles.items()):
        for mod in meta.get("modules", []):
            path = directory / mod
            if not path.exists():
                continue
            text = path.read_text(errors="ignore")
            text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
            body = "\n".join(
                ln for ln in text.split("\n") if not ln.strip().startswith("#")
            ).lstrip()
            if not body.startswith("{"):
                continue
            depth = 0
            for i, ch in enumerate(body):
                if ch == "{":
                    depth += 1
                elif ch == "}":
                    depth -= 1
                    if depth == 0:
                        args, rest = body[: i + 1], body[i + 1 :].lstrip()
                        if rest.startswith(":") and "..." not in args:
                            problems.append(
                                f"{path.relative_to(ROOT)}: claimed as a module, but its "
                                "argument list is fixed — it is a helper or a package "
                                'derivation. Move it to "unclaimed" and import it '
                                "explicitly where it is needed."
                            )
                        break

    # Every relative import must resolve. Comments are stripped first: a
    # commented-out import is a note, not a reference, and counting it would
    # both hide dead modules and flag paths that were deliberately retired.
    def strip_comments(text: str) -> str:
        text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
        return "\n".join(re.sub(r"#.*$", "", ln) for ln in text.split("\n"))

    tracked = subprocess.run(
        ["git", "ls-files", "*.nix"], cwd=ROOT, capture_output=True, text=True
    ).stdout.split()
    for rel in tracked:
        path = ROOT / rel
        if not path.is_file():
            continue
        body = strip_comments(path.read_text(errors="ignore"))
        # ANY relative path, not just .nix. A module also reaches for dotfiles,
        # scripts, images and certificates by relative path, and those break on
        # a move exactly as imports do — but more quietly, because nix turns an
        # over-deep ../ into an absolute /nix/store path and only complains at
        # BUILD time with "access to absolute path ... is forbidden in pure
        # evaluation mode". Checking .nix alone let a moved module reference
        # ../../../dotfiles/… from a directory one level shallower, which
        # evaluated fine and failed the rebuild.
        for match in re.finditer(r"(\.{1,2}(?:/[\w.@+-]+)+)", body):
            imp = match.group(1)
            # Skip interpolated paths — ./tests/test-${hostname}.nix matches
            # only its literal prefix, which of course does not exist.
            if body[match.end() : match.end() + 2] == "${":
                continue
            if imp.endswith((".", "..")):
                continue
            if not (path.parent / imp).exists():
                problems.append(f"{rel}: refers to {imp}, which does not exist")

    # A bundle directory must not contain a default.nix.
    #
    # nix imports a directory by loading its default.nix, so such a file can
    # pull in modules and define options entirely outside the bundle's module
    # list — invisible to every check here, because they all skip default.nix
    # by name. That is exactly how kartoza.cosmic went missing: the option was
    # defined in cosmic/default.nix, which no bundle claimed and nothing
    # imported once the profile stopped importing the directory.
    for name, (directory, _meta) in sorted(bundles.items()):
        if (directory / "default.nix").exists():
            problems.append(
                f"{directory.relative_to(ROOT)}/default.nix: a bundle directory "
                "must not have one — it imports modules outside the bundle's "
                "list and is skipped by these checks. Give it a real name and "
                'add it to "modules".'
            )

    # Every bundle.json must be TRACKED BY GIT.
    #
    # Flake evaluation reads the git tree, not the working tree, so an
    # untracked bundle.json is invisible to nix while being perfectly visible
    # to this checker — which reads the filesystem. The two then disagree, and
    # the failure is a nix "Unknown bundle" throw listing every bundle except
    # the ones you just added. Twelve new bundles hit this at once.
    tracked_files = set(
        subprocess.run(
            ["git", "ls-files", "software/"], cwd=ROOT, capture_output=True, text=True
        ).stdout.split()
    )
    for name, (directory, _meta) in sorted(bundles.items()):
        rel = f"{directory.relative_to(ROOT)}/bundle.json"
        if rel not in tracked_files:
            problems.append(
                f"{rel}: not tracked by git, so nix cannot see it — `git add` it"
            )

    # A host may only name bundles that exist.
    for cfg in sorted((ROOT / "hosts").glob("*/config.nix")):
        block = re.search(r"bundles = \[(.*?)\];", cfg.read_text(), re.S)
        if not block:
            continue
        for named in re.findall(r'"([^"]+)"', block.group(1)):
            if named not in bundles:
                problems.append(
                    f"{cfg.relative_to(ROOT)}: declares bundle {named!r}, "
                    "which does not exist"
                )

    # Documentation that names a module path must name one that exists.
    #
    # This is the drift the bundle work is meant to end. Within an hour of
    # moving the QGIS source builds, README.md was describing a file at its old
    # path — and it had been describing zfs-encryption.nix for however long
    # since that module was last touched. Prose goes stale silently; a check
    # does not.
    doc_files = subprocess.run(
        ["git", "ls-files", "*.md"], cwd=ROOT, capture_output=True, text=True
    ).stdout.split()
    for rel in doc_files:
        if rel.startswith("tim-personal-servers/") or rel == "CHANGELOG.md":
            continue
        path = ROOT / rel
        if not path.is_file():
            continue
        for ref in set(re.findall(r"software/[\w./-]+\.nix", path.read_text(errors="ignore"))):
            if not (ROOT / ref).exists():
                problems.append(f"{rel}: refers to {ref}, which does not exist")

    # The generated reference must be both CURRENT and STABLE.
    #
    # Current: regenerating it produces no diff, so the page cannot describe a
    # taxonomy the tree no longer has.
    #
    # Stable: it must also survive markdownlint unchanged. The generator used
    # to emit `_italic_` and bare URLs; the linter rewrote both, and the next
    # regeneration put them back. Two tools undoing each other on every
    # commit, each blaming the other, neither wrong.
    generated = ROOT / "docs" / "references" / "bundles.md"
    if generated.exists():
        before = generated.read_text()
        gen = subprocess.run(
            [sys.executable, "docs/scripts/generate-bundle-docs.py"],
            cwd=ROOT, capture_output=True, text=True,
        )
        if gen.returncode != 0:
            problems.append(f"docs/scripts/generate-bundle-docs.py failed: {gen.stderr.strip()}")
        elif generated.read_text() != before:
            problems.append(
                "docs/references/bundles.md is out of date — "
                "run python3 docs/scripts/generate-bundle-docs.py"
            )

    total_modules = sum(len(m.get("modules", [])) for _, m in bundles.values())
    total_unclaimed = sum(len(m.get("unclaimed", [])) for _, m in bundles.values())

    if problems:
        print("bundle problems:")
        for p in problems:
            print(f"  ✗ {p}")
        return 1

    print(
        f"✓ {len(bundles)} bundles, {total_modules} modules claimed, "
        f"{total_unclaimed} deliberately unclaimed, "
        f"all imports and doc references resolve"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
