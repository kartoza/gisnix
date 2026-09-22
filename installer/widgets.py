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
        border: solid $secondary;
        padding: 1 2;
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
        # Spaced out, not packed tight — a wider control reads as more
        # prominent/"bigger" than the same 9 marks jammed together, which
        # is the one part of this control actually adjustable: the number
        # of selectable sizes is fixed by what Terminus's "v" charset
        # ships (12-32, in FONT_SIZES above) — there is no ter-v36n or
        # ter-v8n file to fall back to, so that range itself can't grow.
        track = "  ".join("●" if i == self._index else "─" for i in range(len(FONT_SIZES)))
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
#: the network screen jumps around as the pulse plays. Doubled from the
#: first cut (11) at the operator's request — big enough to carry a
#: status word across its own middle row, not just read as a coloured dot.
_CANVAS = 22
_CANVAS_ROWS = (_CANVAS + 1) // 2  # two sub-pixel rows per half-block terminal row
_TEXT_ROW = _CANVAS_ROWS // 2  # the one terminal row the status label prints on

#: "3x3 half pixel dimension" — the fully-collapsed pulse point between
#: phases, per spec. Unchanged by the radius doubling above: this is the
#: pinch point, not a fraction of the max.
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

#: One label per phase, printed across the circle's own middle row —
#: replaces a separate status line below it. "Connection Failed" (17
#: chars) is the longest and still leaves 5 columns of breathing room
#: inside a 22-wide circle.
CIRCLE_LABEL_IDLE = "Preparing"
CIRCLE_LABEL_CHECKING = "Checking"
CIRCLE_LABEL_OK = "Connected"
CIRCLE_LABEL_FAIL = "Connection Failed"


def _ease_in_out_cubic(t: float) -> float:
    """Smooth accel/decel/accel/decel — a linear shrink/grow reads as
    mechanical; this reads as a breath, and it's what gives the pulse its
    lingering pause right at the pinch point between the shrink and grow
    halves."""
    if t < 0.5:
        return 4 * t * t * t
    p = -2 * t + 2
    return 1 - (p * p * p) / 2


def _reveal_centered(text: str, frac: float) -> str:
    """The centre `len(text) * frac` characters of `text` — frac 0 is
    empty, frac 1 is the whole word. Growing this fraction in lockstep
    with the circle's own diameter is what makes the label look like it
    grows outward from the centre with the circle instead of just
    popping in/out at some fixed size."""
    frac = max(0.0, min(1.0, frac))
    n = round(len(text) * frac)
    if n <= 0:
        return ""
    start = (len(text) - n) // 2
    return text[start : start + n]


def _circle_frame(diameter: float, color: str, label: str = "") -> Text:
    """Rasterise a filled circle of `diameter` sub-pixels, centred on a
    fixed _CANVAS x _CANVAS grid, packed two sub-pixel-rows per terminal
    row via half-block characters (█ both on, ▀ top only, ▄ bottom only —
    the same block-glyph family already relied on for the corner logo
    badge, so this is drawing with characters already confirmed to render
    on the console font). `label`, if given, replaces the exact middle
    terminal row with that word (or a centre-out partial reveal of it,
    scaled to how open the circle currently is) instead of circle glyphs
    — the status text riding along inside the circle rather than sitting
    in a separate line below it."""
    radius = diameter / 2
    center = (_CANVAS - 1) / 2
    span = _MAX_DIAMETER - _MIN_DIAMETER
    frac = (diameter - _MIN_DIAMETER) / span if span else 1.0
    revealed = _reveal_centered(label, frac) if label else ""

    def inside(x: float, y: float) -> bool:
        return (x - center) ** 2 + (y - center) ** 2 <= radius * radius

    style = Style(color=color, bold=True)
    lines = []
    for row_index, top_row in enumerate(range(0, _CANVAS, 2)):
        if row_index == _TEXT_ROW and revealed:
            pad = _CANVAS - len(revealed)
            left = max(pad // 2, 0)
            right = max(_CANVAS - left - len(revealed), 0)
            lines.append(" " * left + revealed + " " * right)
            continue
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
    gray "Preparing" -> orange "Checking" -> green "Connected" / red
    "Connection Failed", the label printed across the circle's own
    middle row rather than in a separate line below it. Each phase holds
    for at least _HOLD_SECONDS; each transition between phases is an
    eased pulse — shrink to the 3x3 minimum (taking its label down to
    nothing with it, via _reveal_centered), then grow back in the new
    colour with the new label growing back in alongside it — lasting at
    least _TRANSITION_SECONDS, counted separately from hold time. The
    real connectivity check can itself take several seconds (see
    repo.network_is_up's curl timeout); this keeps that wait visibly
    alive instead of a frozen screen, and report_result() only advances
    the animation once its own minimum ORANGE hold has already elapsed,
    whichever finishes last."""

    DEFAULT_CSS = f"""
    NetworkStatusCircle {{
        width: {_CANVAS};
        height: {_CANVAS_ROWS};
        margin: 1 0;
    }}
    """

    def __init__(self, id: str | None = None) -> None:
        super().__init__(
            _circle_frame(_MAX_DIAMETER, CIRCLE_COLOR_IDLE, CIRCLE_LABEL_IDLE), id=id
        )
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
            self._render_transition(
                elapsed,
                CIRCLE_COLOR_IDLE,
                CIRCLE_COLOR_CHECKING,
                CIRCLE_LABEL_IDLE,
                CIRCLE_LABEL_CHECKING,
            )
            if elapsed >= _TRANSITION_SECONDS:
                self._advance("orange_hold")
        elif self._phase == "orange_hold":
            if elapsed >= _HOLD_SECONDS and self._result is not None:
                self._advance("to_result")
        elif self._phase == "to_result":
            target_color = CIRCLE_COLOR_OK if self._result else CIRCLE_COLOR_FAIL
            target_label = CIRCLE_LABEL_OK if self._result else CIRCLE_LABEL_FAIL
            self._render_transition(
                elapsed, CIRCLE_COLOR_CHECKING, target_color, CIRCLE_LABEL_CHECKING, target_label
            )
            if elapsed >= _TRANSITION_SECONDS:
                self._advance("result_hold")
        # result_hold: final frame already drawn by _advance, nothing more to tick.

    def _advance(self, phase: str) -> None:
        self._phase = phase
        self._phase_start = time.monotonic()
        if phase == "orange_hold":
            self.update(_circle_frame(_MAX_DIAMETER, CIRCLE_COLOR_CHECKING, CIRCLE_LABEL_CHECKING))
        elif phase == "result_hold":
            final_color = CIRCLE_COLOR_OK if self._result else CIRCLE_COLOR_FAIL
            final_label = CIRCLE_LABEL_OK if self._result else CIRCLE_LABEL_FAIL
            self.update(_circle_frame(_MAX_DIAMETER, final_color, final_label))
            if self._timer is not None:
                self._timer.stop()

    def _render_transition(
        self, elapsed: float, from_color: str, to_color: str, from_label: str, to_label: str
    ) -> None:
        t = min(elapsed / _TRANSITION_SECONDS, 1.0)
        if t < 0.5:
            local = _ease_in_out_cubic(t * 2)
            diameter = _MAX_DIAMETER - (_MAX_DIAMETER - _MIN_DIAMETER) * local
            color, label = from_color, from_label
        else:
            local = _ease_in_out_cubic((t - 0.5) * 2)
            diameter = _MIN_DIAMETER + (_MAX_DIAMETER - _MIN_DIAMETER) * local
            color, label = to_color, to_label
        self.update(_circle_frame(diameter, color, label))


def _fill_bar_text(width: int, fill: float, color: str) -> Text:
    """A horizontal bar, `fill` (0..1) of `width` filled with solid
    blocks — the same whole-character-only glyph rule as the circle
    (no eighth-block partial-fill glyphs; the console font's coverage of
    those is exactly what app.py's ToggleButton comment already flags as
    unreliable), shared by both GitHubCheckBar and PasswordStrengthBar."""
    width = max(width, 1)
    filled = round(width * max(0.0, min(1.0, fill)))
    return Text("█" * filled + " " * (width - filled), style=Style(color=color, bold=True))


class GitHubCheckBar(Static):
    """A horizontal fill bar under the GitHub-username field on the user
    screen, started when that field loses focus (see UserScreen's focus
    poll — deliberately not on every keystroke, since this drives a real
    network request per check). Fills toward 90% while the real
    github.com/<user>.keys fetch is in flight (orange, same palette as
    NetworkStatusCircle), holds there for at least _HOLD_SECONDS or until
    the fetch resolves (whichever is later), then finishes filling to
    100% in green (keys found) or red (invalid user / no keys). Unlike
    the circle's pulse, a progress bar only ever fills forward — there is
    no shrink here, that reads as "undoing progress" for this widget."""

    #: Never quite full until there's a real answer — same idea as the
    #: circle never settling on its final colour before its result is in.
    _CHECKING_FILL = 0.9

    DEFAULT_CSS = """
    GitHubCheckBar {
        width: 1fr;
        height: 1;
        margin: 0 0 1 0;
    }
    """

    def __init__(self, id: str | None = None) -> None:
        super().__init__("", id=id)
        self._phase = "idle"
        self._phase_start = 0.0
        self._result: bool | None = None
        self._timer = None

    def start_check(self) -> None:
        """Call when the field blurs with a new, non-empty value."""
        if self._timer is not None:
            self._timer.stop()
        self._phase = "checking"
        self._phase_start = time.monotonic()
        self._result = None
        self._timer = self.set_interval(1 / 20, self._tick)

    def reset(self) -> None:
        """Call when the field is cleared — no username, nothing to show."""
        if self._timer is not None:
            self._timer.stop()
            self._timer = None
        self._phase = "idle"
        self.update("")

    def report_result(self, ok: bool) -> None:
        """Call once the real fetch resolves — may land before or after
        the minimum checking-hold ends; _tick() applies it as soon as
        both are true."""
        self._result = ok

    def _tick(self) -> None:
        elapsed = time.monotonic() - self._phase_start
        if self._phase == "checking":
            t = min(elapsed / _TRANSITION_SECONDS, 1.0)
            fill = self._CHECKING_FILL * _ease_in_out_cubic(t)
            self.update(_fill_bar_text(self.size.width, fill, CIRCLE_COLOR_CHECKING))
            if elapsed >= _TRANSITION_SECONDS:
                self._phase = "checking_hold"
                self._phase_start = time.monotonic()
        elif self._phase == "checking_hold":
            if elapsed >= _HOLD_SECONDS and self._result is not None:
                self._phase = "to_result"
                self._phase_start = time.monotonic()
        elif self._phase == "to_result":
            t = min(elapsed / _TRANSITION_SECONDS, 1.0)
            eased = _ease_in_out_cubic(t)
            fill = self._CHECKING_FILL + (1 - self._CHECKING_FILL) * eased
            color = CIRCLE_COLOR_OK if self._result else CIRCLE_COLOR_FAIL
            self.update(_fill_bar_text(self.size.width, fill, color))
            if elapsed >= _TRANSITION_SECONDS:
                self._phase = "result_hold"
                if self._timer is not None:
                    self._timer.stop()
        # result_hold: final frame already drawn, nothing more to tick.


#: Score->colour gradient stops for PasswordStrengthBar, shared with the
#: rest of the wizard's status palette (red = FAIL, orange = CHECKING,
#: green = OK) rather than inventing a fourth colour scheme.
_STRENGTH_STOPS = [
    (0.0, CIRCLE_COLOR_FAIL),
    (0.5, CIRCLE_COLOR_CHECKING),
    (1.0, CIRCLE_COLOR_OK),
]

_PASSWORD_TRANSITION_SECONDS = 0.3


def _hex_to_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16))


def _rgb_to_hex(rgb: tuple[float, float, float]) -> str:
    return "#{:02X}{:02X}{:02X}".format(*(round(max(0, min(255, c))) for c in rgb))


def _lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def _strength_color(score: float) -> str:
    """Interpolate red -> orange -> green across the three stops above,
    rather than a hard cutoff — the colour itself eases with the score
    the same way the fill/pulse animations ease with time."""
    score = max(0.0, min(1.0, score))
    stops = [(s, _hex_to_rgb(c)) for s, c in _STRENGTH_STOPS]
    for (s0, c0), (s1, c1) in zip(stops, stops[1:]):
        if s0 <= score <= s1:
            local_t = (score - s0) / (s1 - s0) if s1 > s0 else 0.0
            return _rgb_to_hex(tuple(_lerp(c0[i], c1[i], local_t) for i in range(3)))
    return _rgb_to_hex(stops[-1][1])


def _password_strength(password: str) -> float:
    """A deliberately simple 0..1 heuristic — length (the single biggest
    real-world factor per NIST guidance) weighted above character-class
    variety. Advisory only: on_next() still only requires a non-empty,
    matching password. This is a glance-able "does this look weak"
    meter, not a policy gate and not a real entropy estimate."""
    if not password:
        return 0.0
    length_score = min(len(password) / 20, 1.0)
    classes = sum(
        (
            any(c.islower() for c in password),
            any(c.isupper() for c in password),
            any(c.isdigit() for c in password),
            any(not c.isalnum() for c in password),
        )
    )
    variety_score = classes / 4
    return max(0.0, min(1.0, 0.65 * length_score + 0.35 * variety_score))


class _AnimatedFillBar(Static):
    """Shared "ease the current fill+colour toward a new target over a
    fixed duration" engine for PasswordStrengthBar and PasswordMatchBar.
    Both react to live typing rather than a background check, so both
    retarget instantly and just animate the CATCH-UP — unlike the circle
    /GitHubCheckBar's longer hold-then-transition phase machine, which
    exists specifically to make a slow background check visible."""

    DEFAULT_CSS = """
    _AnimatedFillBar {
        width: 1fr;
        height: 1;
        margin: 0 0 1 0;
    }
    """

    def __init__(self, transition_seconds: float, idle_color: str, id: str | None = None) -> None:
        super().__init__("", id=id)
        self._transition_seconds = transition_seconds
        idle_rgb = _hex_to_rgb(idle_color)
        self._current_fill = 0.0
        self._current_rgb = idle_rgb
        self._start_fill = 0.0
        self._start_rgb = idle_rgb
        self._target_fill = 0.0
        self._target_rgb = idle_rgb
        self._anim_start = 0.0
        self._timer = None

    def _retarget(self, fill: float, color: str) -> None:
        self._start_fill = self._current_fill
        self._start_rgb = self._current_rgb
        self._target_fill = fill
        self._target_rgb = _hex_to_rgb(color)
        self._anim_start = time.monotonic()
        if self._timer is None:
            self._timer = self.set_interval(1 / 20, self._tick)

    def _tick(self) -> None:
        t = min((time.monotonic() - self._anim_start) / self._transition_seconds, 1.0)
        eased = _ease_in_out_cubic(t)
        self._current_fill = _lerp(self._start_fill, self._target_fill, eased)
        self._current_rgb = tuple(
            _lerp(self._start_rgb[i], self._target_rgb[i], eased) for i in range(3)
        )
        self.update(_fill_bar_text(self.size.width, self._current_fill, _rgb_to_hex(self._current_rgb)))
        if t >= 1.0 and self._timer is not None:
            self._timer.stop()
            self._timer = None


class PasswordStrengthBar(_AnimatedFillBar):
    """A live fill bar under the password field, recomputed on every
    keystroke (UserScreen.on_input_changed) — length/variety combine into
    a 0..1 score (_password_strength), mapped to a red -> orange -> green
    fill+colour (_strength_color) that eases toward its new target rather
    than jumping, so fast typing still reads as smooth motion."""

    def __init__(self, id: str | None = None) -> None:
        super().__init__(_PASSWORD_TRANSITION_SECONDS, CIRCLE_COLOR_FAIL, id=id)

    def update_password(self, password: str) -> None:
        score = _password_strength(password)
        self._retarget(score if password else 0.0, _strength_color(score))


#: Deliberately longer than the strength bar's 0.3s — "do these two
#: fields match" is a single yes/no answer, not a continuously-refining
#: score, so the fill has room to be a visible, unhurried beat of
#: feedback rather than a flicker, per spec ("minimum duration so the
#: animation is noticeable"). Still non-blocking: it's an independent
#: set_interval ticking the widget, not a sleep in the input handler —
#: typing in either field is never held up by it.
_MATCH_TRANSITION_SECONDS = 1.0


class PasswordMatchBar(_AnimatedFillBar):
    """Fills to green (match) or red (mismatch) whenever the confirm
    field's relationship to the password field changes; an empty confirm
    field resets to empty — nothing to compare yet isn't the same as a
    mismatch."""

    def __init__(self, id: str | None = None) -> None:
        super().__init__(_MATCH_TRANSITION_SECONDS, CIRCLE_COLOR_FAIL, id=id)

    def update_match(self, password: str, confirm: str) -> None:
        if not confirm:
            self._retarget(0.0, CIRCLE_COLOR_FAIL)
            return
        self._retarget(1.0, CIRCLE_COLOR_OK if password == confirm else CIRCLE_COLOR_FAIL)
