#!/usr/bin/env python3
"""Verify the command manifest agrees with every surface it mints.

utils/commands.json is the single source of truth for operator commands. It
feeds four places: the flake's apps, the utils/ scripts, the `hp` cheat-sheet,
and the Neovim <leader>p menu. Nothing enforces that agreement at build time —
a duplicate key silently shadows a binding, a missing prelude fails only when
the app is built, and an editor mapping that collides with a manifest key just
disappears because which-key registers the manifest last.

This is the check that catches all of that. Run it from the repo root; it is
also wired into pre-commit.
"""

from __future__ import annotations

import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def strip_lua_comments(text: str) -> str:
    """Drop -- line comments so binding scans do not match prose about them."""
    return "\n".join(re.sub(r"--.*$", "", ln) for ln in text.splitlines())


def strip_vim_comments(text: str) -> str:
    """Drop " line comments, which is how .exrc documents itself."""
    return "\n".join(ln for ln in text.splitlines() if not ln.lstrip().startswith('"'))


def main() -> int:
    manifest = json.loads((ROOT / "utils/commands.json").read_text())
    cmds = manifest["commands"]
    problems: list[str] = []

    # A duplicate key is the dangerous one: which-key keeps the last
    # registration, so one command silently becomes unreachable.
    seen: dict[str, str] = {}
    for c in cmds:
        if c["key"] in seen:
            problems.append(f"duplicate key {c['key']!r}: {seen[c['key']]} and {c['name']}")
        seen[c["key"]] = c["name"]

    # A group missing from `groups` sorts to the end silently, which reads as
    # the cheat-sheet having lost its ordering rather than as a typo.
    declared_groups = manifest.get("groups", [])
    for c in cmds:
        if c["group"] not in declared_groups:
            problems.append(
                f"{c['name']}: group {c['group']!r} is not in the manifest's `groups` list"
            )

    for c in cmds:
        for dep in c["deps"]:
            if not re.fullmatch(r"[A-Za-z0-9._-]+", dep):
                problems.append(f"{c['name']}: implausible nixpkgs attribute {dep!r}")

    # `pythonDeps` builds an interpreter with those libraries inside it and
    # puts it on PATH ahead of `deps`. A row listing python3 as well would put
    # a second, bare interpreter on the same PATH, and which one won would
    # decide whether the command's imports resolve.
    for c in cmds:
        for dep in c.get("pythonDeps", []):
            if not re.fullmatch(r"[A-Za-z0-9._-]+", dep):
                problems.append(f"{c['name']}: implausible python library {dep!r}")
        if c.get("pythonDeps") and "python3" in c["deps"]:
            problems.append(
                f"{c['name']}: declares pythonDeps and also python3 in deps; "
                "drop python3, the generated interpreter provides it"
            )

    present = []
    for c in cmds:
        ok = (ROOT / "utils" / c["file"]).exists()
        for lib in c.get("prelude", []):
            if not (ROOT / "utils/lib" / lib).exists():
                ok = False
                problems.append(f"{c['name']}: prelude utils/lib/{lib} does not exist")
        if ok:
            present.append(c)
            script = ROOT / "utils" / c["file"]
            if not script.stat().st_mode & 0o111:
                problems.append(f"{c['name']}: utils/{c['file']} is not executable")

    # Editor surfaces must not claim a single-character key the manifest owns.
    surfaces = [
        (".nvim.lua", strip_lua_comments((ROOT / ".nvim.lua").read_text())),
        (".exrc", strip_vim_comments((ROOT / ".exrc").read_text())),
    ]
    for name, text in surfaces:
        for key in re.findall(r"<leader>p(.)(?![A-Za-z])", text):
            if key in seen:
                problems.append(
                    f"{name} binds <leader>p{key}, which the manifest claims for {seen[key]}"
                )

    # The generated reference must be current. It is produced from this very
    # manifest, so a command renamed here and not regenerated leaves the docs
    # describing a command that no longer exists — the exact drift the
    # single-source-of-truth arrangement exists to prevent.
    generated = ROOT / "docs" / "references" / "commands.md"
    generator = ROOT / "docs" / "scripts" / "generate-commands-docs.py"
    if generator.exists() and generated.exists():
        before = generated.read_text()
        run = subprocess.run(
            [sys.executable, str(generator)], cwd=ROOT, capture_output=True, text=True
        )
        if run.returncode != 0:
            problems.append(f"generate-commands-docs.py failed: {run.stderr.strip()}")
        elif generated.read_text() != before:
            problems.append(
                "docs/references/commands.md is out of date — "
                "run python3 docs/scripts/generate-commands-docs.py"
            )

    print(f"commands     {len(cmds)}")
    print(f"implemented  {len(present)}")
    print(f"pending      {len(cmds) - len(present)}")
    groups: dict[str, int] = {}
    for c in cmds:
        groups[c["group"]] = groups.get(c["group"], 0) + 1
    print("groups       " + ", ".join(f"{g}({n})" for g, n in groups.items()))
    print()

    if problems:
        print("PROBLEMS")
        for p in problems:
            print(f"  ✗ {p}")
        return 1
    print("✓ manifest, .nvim.lua and .exrc agree")
    return 0


if __name__ == "__main__":
    sys.exit(main())
