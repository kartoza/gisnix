"""Widgets shared across more than one wizard step.

FontSizeSlider lives here rather than in welcome.py because it isn't really
about the welcome screen — it's a general "adjust and see it happen live"
control that happens to be placed there first.
"""

from __future__ import annotations

import subprocess

from textual.binding import Binding
from textual.widgets import Static

#: Every normal-weight size terminus-font's "v" charset actually ships
#: (confirmed against its own Makefile — PSF_XOS4_2), so every step here is
#: guaranteed to exist rather than guessed at. 12pt has no bold companion in
#: upstream, which doesn't matter here since nothing asks for bold.
FONT_SIZES = [12, 14, 16, 18, 20, 22, 24, 28, 32]

#: Matches the live ISO's own fixed console font (installer.nix sets
#: ter-v32n unconditionally) — the one size actually confirmed to render
#: correctly, in multiple screenshots, on real console hardware. Every
#: OTHER size in FONT_SIZES is only ever exercised live, on the ISO's own
#: console, during the wizard itself — a genuinely different code path
#: from what the INSTALLED system boots with, and untested there. A
#: garbled post-install console (unreadable, not just unattractive —
#: confirmed against a real install) traced to exactly that: the
#: installed system defaulted to a smaller, never-independently-confirmed
#: size instead of the one already proven. Change this back down only
#: once a smaller size has been confirmed against a real POST-INSTALL
#: boot, not just the live ISO.
DEFAULT_FONT_SIZE = 32


def set_console_font_size(size: int) -> None:
    """Best-effort, silent on failure: a cosmetic font swap should never be
    the thing that breaks the install. `setfont` (from `kbd`, already on
    every NixOS system) takes a bare name and searches the console-fonts
    directories `console.packages` wires into the running system's profile
    — no path needed, same as typing it at a shell prompt."""
    try:
        subprocess.run(
            ["setfont", f"ter-v{size}n"],
            check=False,
            capture_output=True,
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        pass


class FontSizeSlider(Static, can_focus=True):
    """Left/right steps through FONT_SIZES, applying each choice immediately.

    There is no such thing as "preview" for a console font — the glyphs
    either look right at this size on this display or they don't — so
    applying it live, one keypress at a time, IS the preview.
    """

    DEFAULT_CSS = """
    FontSizeSlider {
        border: solid $surface-lighten-2;
        padding: 0 1;
        height: auto;
        margin-top: 1;
    }
    FontSizeSlider:focus {
        border: solid $accent;
        background: $accent 20%;
    }
    """

    BINDINGS = [
        Binding("left", "smaller", "Smaller", show=False),
        Binding("right", "bigger", "Bigger", show=False),
    ]

    def __init__(self, initial_size: int = DEFAULT_FONT_SIZE, id: str | None = None) -> None:
        self._index = FONT_SIZES.index(initial_size) if initial_size in FONT_SIZES else FONT_SIZES.index(
            DEFAULT_FONT_SIZE
        )
        # Static needs a real renderable at construction time — leaving it
        # empty until on_mount() calls update() crashes the very first
        # layout pass (get_content_height sees no visual yet to measure).
        super().__init__(self._track_text(), id=id)

    @property
    def size_pt(self) -> int:
        return FONT_SIZES[self._index]

    def on_mount(self) -> None:
        set_console_font_size(self.size_pt)

    def action_smaller(self) -> None:
        if self._index > 0:
            self._index -= 1
            self._apply()

    def action_bigger(self) -> None:
        if self._index < len(FONT_SIZES) - 1:
            self._index += 1
            self._apply()

    def _apply(self) -> None:
        self.update(self._track_text())
        set_console_font_size(self.size_pt)

    def _track_text(self) -> str:
        track = "".join("●" if i == self._index else "─" for i in range(len(FONT_SIZES)))
        return (
            f"[b]Console font size[/b]  ←  {track}  →  [b]{self.size_pt}pt[/b]\n"
            "[dim]Focus this control (click or Tab) and press ←/→ — the console font "
            "changes immediately, so pick whatever's actually comfortable to read.[/dim]"
        )
