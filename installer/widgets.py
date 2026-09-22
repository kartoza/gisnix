"""Standalone widgets, kept out of the screen files that use them so each
screen file stays about wizard flow (fields, validation, on_next) rather
than widget mechanics.

FontSizeSlider isn't really about the welcome screen — it's a general
"adjust and see it happen live" control that happens to be placed there
first. NetworkStatusCircle is the network-check screen's animated status
indicator.

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
import time

from rich.style import Style
from rich.text import Text
from textual.binding import Binding
from textual.widgets import Static

from . import branding
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


#: Sub-pixel grid size the circle is rasterised onto. Fixed for every
#: frame — the CIRCLE's diameter shrinks/grows, but the canvas it's drawn
#: on doesn't, so the widget's own size never changes and nothing else on
#: the network screen jumps around as the pulse plays. Odd, so there's a
#: true centre cell.
_CANVAS = 11
_CANVAS_ROWS = (_CANVAS + 1) // 2  # two sub-pixel rows per half-block terminal row

#: "3x3 half pixel dimension" — the fully-collapsed pulse point between
#: phases, per spec.
_MIN_DIAMETER = 3
_MAX_DIAMETER = _CANVAS

_HOLD_SECONDS = 2.0
_TRANSITION_SECONDS = 2.0

_PALETTE = branding.textual_css_vars()
CIRCLE_COLOR_IDLE = _PALETTE["muted"]
CIRCLE_COLOR_CHECKING = _PALETTE["accent"]
CIRCLE_COLOR_FAIL = _PALETTE["danger"]
#: brand.nix has no green role (its four highlights are gold/blue/grey/
#: teal) — a plain, unambiguous success green rather than stretching one
#: of those to mean something it doesn't elsewhere in the wizard.
CIRCLE_COLOR_OK = "#4CAF50"


def _ease_in_out_cubic(t: float) -> float:
    """Smooth accel/decel/accel/decel — a linear shrink/grow reads as
    mechanical; this reads as a breath, and it's what gives the pulse its
    lingering pause right at the pinch point between the shrink and grow
    halves."""
    if t < 0.5:
        return 4 * t * t * t
    p = -2 * t + 2
    return 1 - (p * p * p) / 2


def _circle_frame(diameter: float, color: str) -> Text:
    """Rasterise a filled circle of `diameter` sub-pixels, centred on a
    fixed _CANVAS x _CANVAS grid, packed two sub-pixel-rows per terminal
    row via half-block characters (█ both on, ▀ top only, ▄ bottom only —
    the same block-glyph family already relied on for the corner logo
    badge, so this is drawing with characters already confirmed to render
    on the console font)."""
    radius = diameter / 2
    center = (_CANVAS - 1) / 2

    def inside(x: float, y: float) -> bool:
        return (x - center) ** 2 + (y - center) ** 2 <= radius * radius

    style = Style(color=color, bold=True)
    lines = []
    for top_row in range(0, _CANVAS, 2):
        bottom_row = top_row + 1
        chars = []
        for col in range(_CANVAS):
            top_on = inside(col, top_row)
            bottom_on = bottom_row < _CANVAS and inside(col, bottom_row)
            if top_on and bottom_on:
                chars.append("█")
            elif top_on:
                chars.append("▀")
            elif bottom_on:
                chars.append("▄")
            else:
                chars.append(" ")
        lines.append("".join(chars))
    return Text("\n".join(lines), style=style)


class NetworkStatusCircle(Static):
    """A small animated status indicator for the network-check screen:
    gray (idle) -> orange (checking) -> green/red (result). Each phase
    holds for at least _HOLD_SECONDS; each transition between phases is
    an eased pulse — shrink to the 3x3 minimum, then grow back, changing
    colour at the pinch point — lasting at least _TRANSITION_SECONDS,
    counted separately from hold time. The real connectivity check can
    itself take several seconds (see repo.network_is_up's curl timeout);
    this keeps that wait visibly alive instead of a frozen screen, and
    report_result() only advances the animation once its own minimum
    ORANGE hold has already elapsed, whichever finishes last."""

    DEFAULT_CSS = f"""
    NetworkStatusCircle {{
        width: {_CANVAS};
        height: {_CANVAS_ROWS};
        margin: 1 0;
    }}
    """

    def __init__(self, id: str | None = None) -> None:
        super().__init__(_circle_frame(_MAX_DIAMETER, CIRCLE_COLOR_IDLE), id=id)
        self._phase = "gray_hold"
        self._phase_start = time.monotonic()
        self._result: bool | None = None
        self._timer = None

    def on_mount(self) -> None:
        self._timer = self.set_interval(1 / 20, self._tick)

    def report_result(self, connected: bool) -> None:
        """Called once the real network check resolves — may fire well
        before or well after the minimum ORANGE hold ends; _tick() picks
        it up as soon as both are true."""
        self._result = connected

    def _tick(self) -> None:
        elapsed = time.monotonic() - self._phase_start

        if self._phase == "gray_hold":
            if elapsed >= _HOLD_SECONDS:
                self._advance("to_orange")
        elif self._phase == "to_orange":
            self._render_transition(elapsed, CIRCLE_COLOR_IDLE, CIRCLE_COLOR_CHECKING)
            if elapsed >= _TRANSITION_SECONDS:
                self._advance("orange_hold")
        elif self._phase == "orange_hold":
            if elapsed >= _HOLD_SECONDS and self._result is not None:
                self._advance("to_result")
        elif self._phase == "to_result":
            target = CIRCLE_COLOR_OK if self._result else CIRCLE_COLOR_FAIL
            self._render_transition(elapsed, CIRCLE_COLOR_CHECKING, target)
            if elapsed >= _TRANSITION_SECONDS:
                self._advance("result_hold")
        # result_hold: final frame already drawn by _advance, nothing more to tick.

    def _advance(self, phase: str) -> None:
        self._phase = phase
        self._phase_start = time.monotonic()
        if phase == "orange_hold":
            self.update(_circle_frame(_MAX_DIAMETER, CIRCLE_COLOR_CHECKING))
        elif phase == "result_hold":
            final = CIRCLE_COLOR_OK if self._result else CIRCLE_COLOR_FAIL
            self.update(_circle_frame(_MAX_DIAMETER, final))
            if self._timer is not None:
                self._timer.stop()

    def _render_transition(self, elapsed: float, from_color: str, to_color: str) -> None:
        t = min(elapsed / _TRANSITION_SECONDS, 1.0)
        if t < 0.5:
            local = _ease_in_out_cubic(t * 2)
            diameter = _MAX_DIAMETER - (_MAX_DIAMETER - _MIN_DIAMETER) * local
            color = from_color
        else:
            local = _ease_in_out_cubic((t - 0.5) * 2)
            diameter = _MIN_DIAMETER + (_MAX_DIAMETER - _MIN_DIAMETER) * local
            color = to_color
        self.update(_circle_frame(diameter, color))
