"""Render mermaid diagrams to SVG at docs-generation time.

Why this exists: mermaid diagrams are drawn client-side by mermaid.js. That is
fine for the HTML site, but the PDF export renders through WeasyPrint, which
cannot execute JavaScript. docs-pdf works around it by driving headless Chrome
with a virtual time budget, which is fragile and still leaves diagrams missing
or half-drawn. Rendering to SVG up front removes the JavaScript from the
critical path entirely: the same SVG is served in HTML and embedded in the PDF.

The diagrams stay in lock-step with the configuration because the callers build
their mermaid source from a live `nix eval` of `nixosConfigurations.<host>`, and
this module is invoked on every docs build. Nothing is hand-drawn, so nothing
can drift.

Both consumers share this one implementation:

  * docs/scripts/generate-host-docs.py — the per-host and fleet diagrams
  * docs/scripts/macros.py — the `diagram()` macro used by hand-written pages

If mermaid-cli is unavailable the source is emitted as a fenced ```mermaid
block instead, so the HTML site still renders and only the PDF loses the
diagram. That keeps a missing tool from failing the whole docs build.
"""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
DIAGRAM_DIR = REPO_ROOT / "docs" / "assets" / "diagrams"

# Chromium inside a nix build/run environment has no setuid sandbox helper, and
# mermaid-cli gives no way to pass browser flags except through this file.
_PUPPETEER_CONFIG = {"args": ["--no-sandbox", "--disable-dev-shm-usage"]}

# htmlLabels is the important one. By default mermaid puts label text inside
# <foreignObject>, i.e. HTML embedded in the SVG. WeasyPrint cannot render
# foreignObject, and hitting one aborts the PDF mid-document — the export
# stopped at the fleet diagram and silently lost every page after it. Turning
# it off makes mermaid emit plain <text>, which WeasyPrint handles.
#
# useMaxWidth: false makes mermaid emit a concrete pixel width instead of
# width="100%", so the SVG has an intrinsic size to lay out against.
_MERMAID_CONFIG = {
    "htmlLabels": False,
    "flowchart": {"htmlLabels": False, "useMaxWidth": False},
    "sequence": {"useMaxWidth": False},
    "gantt": {"useMaxWidth": False},
}

# Folded into the cache digest, so changing how diagrams are rendered
# invalidates every stamp automatically. Without it, a render-option change
# leaves the old SVGs in place because their *source* has not changed — which
# is precisely how the foreignObject problem would have survived this fix.
# Bump on any change to _MERMAID_CONFIG or the post-processing below.
RENDER_VERSION = "2"


def _mmdc() -> str | None:
    return shutil.which("mmdc")


def _fenced(source: str) -> str:
    return "```mermaid\n" + source.rstrip("\n") + "\n```\n"


def render(
    source: str,
    slug: str,
    alt: str,
    *,
    rel_prefix: str = "../assets/diagrams",
    background: str = "transparent",
    diagram_dir: Path | None = None,
) -> str:
    """Render `source` to `<diagram_dir>/<slug>.svg`, return an embed.

    `rel_prefix` is the path from the page that will contain the embed back to
    the diagram directory — `../assets/diagrams` for a page in `docs/hosts/`.

    `diagram_dir` defaults to gisnix's own docs/assets/diagrams — correct for
    macros.py, which only ever renders gisnix's own hand-written pages.
    generate-host-docs.py passes its own (a downstream consumer's own
    docs/assets/diagrams, not gisnix's) explicitly instead, same reasoning as
    that script's own GISNIX_ROOT/TARGET_ROOT split.

    A transparent background is the default so one SVG suits both the light and
    dark site themes as well as the PDF.

    Returns markdown. On any failure it returns a fenced mermaid block, so a
    broken or absent mermaid-cli degrades the PDF rather than breaking the site.
    """
    diagram_dir = diagram_dir if diagram_dir is not None else DIAGRAM_DIR
    source = source.rstrip("\n") + "\n"
    diagram_dir.mkdir(parents=True, exist_ok=True)

    # Keep the source beside the SVG: it is reviewable in a diff, whereas the
    # generated SVG is not, and it lets anyone re-render without this script.
    (diagram_dir / f"{slug}.mmd").write_text(source)

    svg_path = diagram_dir / f"{slug}.svg"

    mmdc = _mmdc()
    if mmdc is None:
        # An SVG that is already here was rendered by somebody who did have
        # mermaid-cli, and is committed. Referring to it keeps the generated
        # MARKDOWN identical whether or not this machine can render — which
        # matters because that markdown is committed and checked: without
        # this, regenerating on a machine without mmdc rewrote every diagram
        # into a fenced block, and the manifest check failed on the
        # difference.
        if svg_path.exists():
            return f"![{alt}]({rel_prefix}/{slug}.svg)\n"
        print(
            f"    mermaid-cli not found and no {slug}.svg yet; "
            "leaving it as a fenced block",
            file=sys.stderr,
        )
        return _fenced(source)

    # Skip the render when the source has not changed. mmdc spawns a headless
    # browser per invocation, so on a full docs build this is the difference
    # between a couple of seconds and the better part of a minute.
    digest = hashlib.sha256((RENDER_VERSION + "\n" + source).encode()).hexdigest()[:16]
    stamp = diagram_dir / f".{slug}.sha"
    if svg_path.exists() and stamp.exists() and stamp.read_text().strip() == digest:
        return f"![{alt}]({rel_prefix}/{slug}.svg)\n"

    with tempfile.TemporaryDirectory() as tmp:
        cfg = Path(tmp) / "puppeteer.json"
        cfg.write_text(json.dumps(_PUPPETEER_CONFIG))
        mcfg = Path(tmp) / "mermaid.json"
        mcfg.write_text(json.dumps(_MERMAID_CONFIG))
        src = Path(tmp) / f"{slug}.mmd"
        src.write_text(source)
        try:
            subprocess.run(
                [
                    mmdc,
                    "--input", str(src),
                    "--output", str(svg_path),
                    "--backgroundColor", background,
                    "--puppeteerConfigFile", str(cfg),
                    "--configFile", str(mcfg),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
        except subprocess.CalledProcessError as exc:
            print(f"    mmdc failed for {slug}: {exc.stderr.strip()[:400]}", file=sys.stderr)
            return _fenced(source)

    _make_print_safe(svg_path, slug)
    stamp.write_text(digest)
    return f"![{alt}]({rel_prefix}/{slug}.svg)\n"


def _make_print_safe(svg_path: Path, slug: str) -> None:
    """Give the SVG an intrinsic size and warn if foreignObject survived.

    The mermaid config above should prevent both problems, but the flags have
    moved between mermaid releases and a silently truncated PDF is an expensive
    way to discover a rename. This checks the actual output rather than trusting
    the configuration.
    """
    try:
        svg = svg_path.read_text()
    except OSError:
        return

    if "<foreignObject" in svg:
        print(
            f"    WARNING: {slug}.svg still contains <foreignObject>. WeasyPrint"
            " cannot render it and the PDF will truncate at this diagram."
            " Check that mermaid still honours htmlLabels: false.",
            file=sys.stderr,
        )

    # width="100%" leaves WeasyPrint with no intrinsic size. Replace it with the
    # viewBox dimensions so the diagram lays out in print.
    if 'width="100%"' in svg:
        m = re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', svg)
        if m:
            w, h = float(m.group(1)), float(m.group(2))
            svg = svg.replace(
                'width="100%"', f'width="{w:.0f}" height="{h:.0f}"', 1
            )
            svg_path.write_text(svg)
