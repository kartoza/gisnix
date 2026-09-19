"""mkdocs-macros hooks.

Provides the `diagram()` macro used by hand-written pages, so their mermaid
diagrams are rendered to SVG at build time exactly like the generated ones.
The rendering itself lives in docs/scripts/diagram.py — this file only bridges
mkdocs to it.

Usage in a page:

    {{ diagram("architecture", "How a host is composed") }}

which reads docs/diagrams/architecture.mmd and emits an <img> pointing at the
rendered SVG.

Diagram sources live in docs/diagrams/*.mmd rather than inline in the page so
they are reviewable in a diff, can be re-rendered without mkdocs, and are not
duplicated between the HTML and PDF paths.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import json as _json  # noqa: E402

import brand as _brand  # noqa: E402
import bundles as _bundles  # noqa: E402
import diagram as _diagram  # noqa: E402


REPO_ROOT = Path(__file__).resolve().parent.parent.parent

sys.path.insert(0, str(REPO_ROOT / "utils" / "lib"))

import hostconfig as _hostconfig  # noqa: E402
SOURCE_DIR = REPO_ROOT / "docs" / "diagrams"


MANIFEST = REPO_ROOT / "utils" / "commands.json"


def _manifest() -> dict:
    try:
        return _json.loads(MANIFEST.read_text())
    except (OSError, ValueError):
        return {"groups": [], "commands": []}


def _implemented(command: dict) -> bool:
    return (REPO_ROOT / "utils" / command["file"]).exists()


def _table(headers: list[str], rows: list[list[str]]) -> str:
    if not rows:
        return "_Nothing to show._"
    out = ["| " + " | ".join(headers) + " |",
           "| " + " | ".join("---" for _ in headers) + " |"]
    out += ["| " + " | ".join(r) + " |" for r in rows]
    return "\n".join(out)


def define_env(env):
    @env.macro
    def diagram(slug: str, alt: str = "", page_depth: int = 1) -> str:
        """Render docs/diagrams/<slug>.mmd to SVG and return a markdown embed.

        page_depth is how many directories deep the calling page sits under
        docs/ — 1 for docs/developer/foo.md, 0 for docs/index.md. It only
        affects the relative path back to docs/assets/diagrams/.
        """
        src = SOURCE_DIR / f"{slug}.mmd"
        if not src.exists():
            return (
                f"!!! warning\n\n    Diagram source `docs/diagrams/{slug}.mmd`"
                " does not exist.\n"
            )
        prefix = "../" * page_depth + "assets/diagrams"
        return _diagram.render(
            src.read_text(),
            slug=slug,
            alt=alt or slug.replace("-", " "),
            rel_prefix=prefix,
        )

    # ── Command manifest ──────────────────────────────────────────────────
    # utils/commands.json already mints the flake apps, the cheat-sheet and
    # the Neovim menu. These let a hand-written page quote it too, so prose
    # about a command cannot describe one that has been renamed.

    @env.macro
    def command_reference(group: str | None = None) -> str:
        """Quick index of commands: name, key, one line. Optionally one group."""
        manifest = _manifest()
        rows = []
        for g in manifest["groups"]:
            if group is not None and g != group:
                continue
            members = sorted(
                (c for c in manifest["commands"] if c["group"] == g),
                key=lambda c: c.get("order", 0),
            )
            for c in members:
                pending = "" if _implemented(c) else " *(planned)*"
                rows.append([
                    f"`gisnix {c['name']}`{pending}",
                    f"`<leader>p{c['key']}`",
                    c.get("terse", c["desc"]),
                ])
        return _table(["Command", "Key", "What it does"], rows)

    @env.macro
    def command_sequence(name: str) -> str:
        """The steps a command announces before it runs, as a numbered list.

        `sequence` has been in the manifest since the commands learned to say
        what they were about to do, and only the terminal banner used it. A
        page describing a workflow can now quote the workflow itself.
        """
        command = next(
            (c for c in _manifest()["commands"] if c["name"] == name), None
        )
        if command is None:
            return f"!!! warning\n\n    No command named `{name}` in the manifest."
        steps = command.get("sequence") or []
        if not steps:
            return (
                f"`gisnix {name}` is read-only — it declares no sequence, because "
                "it has no workflow to announce."
            )
        return "\n".join(f"{i}. {s}" for i, s in enumerate(steps, 1))

    @env.macro
    def command_docs(group: str | None = None) -> str:
        """Every command with its usage and dependencies, grouped."""
        manifest = _manifest()
        out = []
        for g in manifest["groups"]:
            if group is not None and g != group:
                continue
            members = sorted(
                (c for c in manifest["commands"] if c["group"] == g),
                key=lambda c: c.get("order", 0),
            )
            if not members:
                continue
            out.append(f"### {g}")
            out.append("")
            for c in members:
                out.append(f"**`{c.get('usage', 'gisnix ' + c['name'])}`**")
                out.append("")
                out.append(c["desc"] + ".")
                out.append("")
                if c.get("sequence"):
                    out += [f"{i}. {s}" for i, s in enumerate(c["sequence"], 1)]
                    out.append("")
        return "\n".join(out)

    # ── Fleet ─────────────────────────────────────────────────────────────

    @env.macro
    def hosts_table() -> str:
        """Every host with the bundles and locale its config.nix declares.

        Read from the files rather than evaluated: this is the cheap view, and
        it is what a reader wants when the question is "which machines take
        the GIS stack" rather than "what exactly does abyss install".
        """
        rows = []
        for host in _hostconfig.hosts():
            config = _hostconfig.parse(_hostconfig.path_for(host))
            rows.append([
                f"[`{host}`](../hosts/{host}.md)",
                str(len(config.enabled)),
                f"`{config.locale}`" if config.locale else "—",
            ])
        return _table(["Host", "Bundles", "Locale"], rows)

    @env.macro
    def host_fields_table() -> str:
        """The fields hosts/fleet.nix records for each machine.

        Derived from the registry itself, so a field added there appears here
        without anyone editing prose. `docs/developer/adding-a-host.md`
        described these by hand, which is how that page fell behind.
        """
        import re as _re

        try:
            text = (REPO_ROOT / "hosts" / "fleet.nix").read_text()
        except OSError:
            return "_hosts/fleet.nix is unreadable._"

        # The first host entry defines the shape; comments beside a field are
        # the only description anybody has written for it.
        rows, seen = [], set()
        for line in text.split("\n"):
            match = _re.match(r"\s{4,}([a-zA-Z][A-Za-z0-9_]*)\s*=\s*(.+?);\s*(?:#\s*(.*))?$", line)
            if not match:
                continue
            field, value, note = match.group(1), match.group(2), match.group(3)
            if field in seen or field in {"hosts", "extra"}:
                continue
            seen.add(field)
            rows.append([f"`{field}`", f"`{value[:32]}`", note or "—"])
        return _table(["Field", "Example", "Notes"], rows[:20])

    # ── Software ──────────────────────────────────────────────────────────

    @env.macro
    def bundle_table() -> str:
        """Every bundle, its module count and what pulls it in."""
        rows = []
        for b in _bundles.load():
            marks = []
            if b.get("required"):
                marks.append("required")
            if b.get("optIn"):
                marks.append("opt-in")
            if b.get("selection") == "one-of":
                marks.append("choice")
            rows.append([
                f"`{b['name']}`",
                str(len(b.get("modules", []))),
                ", ".join(f"`{d}`" for d in b.get("implies", [])) or "—",
                ", ".join(marks) or "—",
            ])
        return _table(["Bundle", "Modules", "Requires", ""], rows)

    # ── Secrets ───────────────────────────────────────────────────────────

    @env.macro
    def secrets_inventory() -> str:
        """Which secrets exist, from secrets/secrets.nix.

        Names only. Who can read each one is a list of public keys, and
        rendering those into a public page would be noise at best.
        """
        import re as _re

        try:
            text = (REPO_ROOT / "secrets" / "secrets.nix").read_text()
        except OSError:
            return "_secrets/secrets.nix is unreadable._"
        names = sorted(set(_re.findall(r'"([^"]+\.age)"', text)))
        if not names:
            return "_No secrets declared._"
        return _table(
            ["Secret"], [[f"`{n}`"] for n in names]
        )

    # ── Brand ─────────────────────────────────────────────────────────────

    @env.macro
    def contrast_table() -> str:
        """WCAG 2.2 contrast for every pairing brand.nix declares.

        Computed, not asserted. The palette is pure data in brand.nix, so a
        colour change is measured here on the next build rather than being
        described by a sentence somebody forgot to update.
        """
        rows = []
        for row in _brand.surface_report():
            verdict = (
                "✅ AA" if row["text"]
                else ("⚠️ large text only" if row["large"] else "❌ fails AA")
            )
            rows.append([
                f"`{row['surface']}`",
                f"`{row['fg']}`",
                f"`{row['bg']}`",
                f"{row['ratio']:.2f}:1",
                verdict,
            ])
        if not rows:
            return "_brand.nix could not be evaluated._"
        return _table(
            ["Surface", "Foreground", "Background", "Ratio", "WCAG 2.2 AA"], rows
        )

    @env.macro
    def brand_palette() -> str:
        """The palette and what each colour means."""
        data = _brand.load()
        if not data:
            return "_brand.nix could not be evaluated._"
        roles = {v: k for k, v in (data.get("roles") or {}).items()}
        rows = [
            [f"`{name}`", f"`{value}`", roles.get(value, "—")]
            for name, value in sorted((data.get("colors") or {}).items())
        ]
        return _table(["Name", "Hex", "Role"], rows)
