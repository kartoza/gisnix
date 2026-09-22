"""Widgets shared across more than one wizard step.

FontSizeSlider lives here rather than in welcome.py because it isn't really
about the welcome screen — it's a general "adjust and see it happen live"
control that happens to be placed there first.

Wizard-console-only, deliberately: `set_console_font_size` calls `setfont`
against the live ISO's own running console and nothing else. It is never
read back into `InstallState` and never reaches `writer.py` — a previous
version threaded the chosen size into the INSTALLED system's
`hardware.nix` via a `state.console_font_size` field, and a default that
drifted out of sync between here and there left every real install booting
into an unreadable 16pt console (see git history: "fix(installer): stop
overriding the installed system's console font"). The installed system
keeps using the kernel's own default font, same as tuinix; this widget's
only job is making the WIZARD itself comfortable to read, for however long
the wizard is open.
"""

from __future__ import annotations

import subprocess

from textual.binding import Binding
from textual.widgets import Static

from .repo import MOCK

#: Every normal-weight size terminus-font's "v" charset actually ships
#: (confirmed against its own Makefile — PSF_XOS4_2), so every step here is
#: guaranteed to exist rather than guessed at. 12pt has no bold companion in
#: upstream, which doesn't matter here since nothing asks for bold.
FONT_SIZES = [12, 14, 16, 18, 20, 22, 24, 28, 32]

#: Matches the live ISO's own fixed console font (installer.nix sets
#: ter-v32n unconditionally) — the one size actually confirmed to render
#: correctly, in multiple screenshots, on real console hardware. This is
#: the ONLY place that number is allowed to live — no second copy of it
#: anywhere else to drift out of sync (that drift is exactly what broke
#: this feature the first time round).
DEFAULT_FONT_SIZE = 32


def set_console_font_size(size: int) -> None:
    """Best-effort, silent on failure: a cosmetic font swap should never be
    the thing that breaks the install. `setfont` (from `kbd`, already on
    every NixOS system) takes a bare name and searches the console-fonts
    directories `console.packages` wires into the running system's profile
    — no path needed, same as typing it at a shell prompt. Affects only the
    live ISO's current console session — nothing here is persisted.

    `setfont` only ever does anything against a real Linux virtual console
    (/dev/ttyN) — it is a no-op under any ordinary terminal emulator
    (kitty, alacritty, a desktop SSH session, ...), which is also how
    `--mock` is normally driven for fast iteration on the wizard itself.
    Skipped outright in that case rather than shelling out for nothing."""
    if MOCK:
        return
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

    def __init__(self, id: str | None = None) -> None:
        self._index = FONT_SIZES.index(DEFAULT_FONT_SIZE)
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
        hint = (
            "[dim]Preview only in --mock: setfont only affects a real Linux "
            "console, not this terminal emulator — try it on the actual live "
            "ISO to see it change anything.[/dim]"
            if MOCK
            else "[dim]Focus this control (click or Tab) and press ←/→ — the console font "
            "changes immediately, so pick whatever's actually comfortable to read. "
            "Only affects this wizard session, not the machine you're installing.[/dim]"
        )
        return f"[b]Console font size[/b]  ←  {track}  →  [b]{self.size_pt}pt[/b]\n{hint}"
