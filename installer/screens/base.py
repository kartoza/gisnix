"""Shared shape for every wizard step: a title, a body the subclass fills
in, and a button bar pinned to the bottom — Back/Cancel on the left, the
step's primary action on the right. Tab cycles focus; Enter activates
whichever button is focused. Mirrors the navigation tuinix's installer
established (see its SPECIFICATION.md) — proven, so kept rather than
reinvented.
"""

from __future__ import annotations

from rich.text import Text
from textual.containers import Container, Horizontal, Vertical, VerticalScroll
from textual.screen import Screen
from textual.widgets import Button, Footer, Header, Static

from .. import branding


class WizardScreen(Screen):
    """Subclass, override `body()` for the step's own widgets and
    `on_next()`/`on_back()` for what Continue/Back should do. Return False
    from `on_next()` to stay on the screen (e.g. validation failed — show
    the error via `self.set_error(...)` first).

    The card fills the whole terminal. The button bar is docked to its
    bottom edge, so Back/Continue stay on screen and reachable no matter
    how much a step's own body() grows — the body scrolls independently
    of them rather than pushing them past the visible frame."""

    BINDINGS = [("escape", "back", "Back")]

    CSS = """
    WizardScreen {
        align: center middle;
    }
    #wizard-card {
        width: 100%;
        height: 100%;
        border: solid $primary;
        padding: 0 1 1 1;
    }
    #wizard-title-row {
        margin: 0 0 1 0;
    }
    #wizard-title {
        background: $primary;
        color: $text;
        text-style: bold;
        padding: 0 1;
        width: 1fr;
        height: 100%;
        content-align: left middle;
    }
    #wizard-step-badge {
        background: $accent;
        color: $ink;
        text-style: bold;
        padding: 0 1;
        width: auto;
        height: 100%;
        content-align: center middle;
    }
    #wizard-logo-badge {
        padding: 0 1;
        height: 100%;
        content-align: center middle;
    }
    #wizard-error {
        color: $error;
        text-style: bold;
        height: auto;
        padding: 0 0 1 0;
    }
    #wizard-body {
        height: 1fr;
        padding: 0 1 1 0;
    }
    #wizard-buttons {
        dock: bottom;
        height: 3;
        align: right middle;
        background: $surface;
    }
    #wizard-buttons Button {
        margin-left: 1;
    }
    #wizard-back {
        dock: left;
    }

    /* A titled, bordered sub-section — groups related fields into one
       visually distinct block instead of a flat scroll of labels. Three
       tones share the same shape: "secondary" for ordinary grouping,
       "accent" to draw the eye to the step's main choice, "danger" for a
       destructive/warning section (e.g. "this erases a disk"). */
    .panel {
        border: solid $secondary;
        height: auto;
        margin: 0 0 1 0;
    }
    .panel-accent {
        border: solid $accent;
    }
    .panel-danger {
        border: solid $danger;
    }
    .panel-title {
        background: $secondary;
        color: $text;
        text-style: bold;
        height: 1;
        padding: 0 1;
    }
    .panel-title-accent {
        background: $accent;
        color: $ink;
    }
    .panel-title-danger {
        background: $danger;
        color: $text;
    }
    /* The "overtone": each panel's body sits on a muted tint of its own
       title colour blended into the screen's dark surface, rather than
       the flat default background — same two-tone card look (bright
       header strip, deep-tinted body) as the sticky notes this design was
       modelled on. Percentage-opacity blend, not a `-darken-N` suffix:
       "secondary"/"accent"/"danger" are brand.nix colours layered on top
       of Textual's own design system (app.py's get_css_variables), not
       part of it — a `-darken-N` companion is only ever generated for
       Textual's own built-in roles, so one doesn't exist for these. The
       opacity-blend form (`$colour N%`) is the same mechanism app.py's
       focus-state CSS already relies on, applied here instead of guessed. */
    .panel .panel-body {
        height: auto;
        padding: 1;
        background: $secondary 25%;
    }
    .panel-accent .panel-body {
        background: $accent 25%;
    }
    .panel-danger .panel-body {
        background: $danger 25%;
    }
    """

    def __init__(self, title: str, next_label: str = "Next", next_variant: str = "primary") -> None:
        super().__init__()
        self._title = title
        self._next_label = next_label
        self._next_variant = next_variant
        self._step_index: int | None = None
        self._step_total: int | None = None

    def set_step(self, index: int, total: int) -> None:
        """Called by InstallerApp right after construction — this screen
        doesn't know its own position, the wizard's step order does."""
        self._step_index = index
        self._step_total = total

    def compose(self):
        yield Header(show_clock=True)
        with Container(id="wizard-card"):
            # Explicit height, not CSS `auto`: title/step-badge/logo all
            # need to stretch to fill it (a colour-filled title strip that
            # only covered its own single text row, floating inside a
            # taller auto-sized row, would look like a broken sliver, not
            # a banner) — 100%-height children inside an auto container is
            # the exact circular case Textual's layout can't resolve, so
            # the row's height is fixed here in Python instead, from the
            # one thing that actually needs more than one row: the badge.
            title_row = Horizontal(id="wizard-title-row")
            title_row.styles.height = branding.corner_badge_rows()
            with title_row:
                yield Static(self._title, id="wizard-title")
                if self._step_total:
                    yield Static(
                        f"Step {self._step_index} of {self._step_total}", id="wizard-step-badge"
                    )
                badge = self._logo_badge()
                if badge is not None:
                    yield badge
            yield Static("", id="wizard-error")
            with VerticalScroll(id="wizard-body"):
                yield from self.body()
            with Horizontal(id="wizard-buttons"):
                yield Button("Back", id="wizard-back")
                yield Button(self._next_label, id="wizard-next", variant=self._next_variant)
        yield Footer()

    def body(self):
        """Override: yield the step's own widgets."""
        return []
        yield  # pragma: no cover - makes this a generator

    def _logo_badge(self) -> Static | None:
        """The tiny Kartoza mark in the title row's right corner, on every
        screen. Parses chafa's ANSI through Rich's own decoder rather than
        handing a raw escape-code string to Static — a raw string's
        wrapping is measured in bytes, so a naive word-wrap can shred an
        escape sequence mid-code; Text.from_ansi turns it into a real Rich
        Text with the colour spans tracked separately from the visible
        characters, and the widget is sized exactly to the render (no wrap
        ever needed) rather than trusting auto-sizing to get it right."""
        ansi = branding.render_corner_badge()
        if not ansi:
            return None
        widget = Static(Text.from_ansi(ansi), id="wizard-logo-badge")
        widget.styles.width = branding.CORNER_BADGE_WIDTH
        return widget

    def panel(self, title: str, *widgets, tone: str = "secondary"):
        """A bordered, titled group of widgets — call with `yield from` from
        inside `body()`. `tone` is "secondary" (default), "accent", or
        "danger"."""
        suffix = f"-{tone}" if tone != "secondary" else ""
        with Container(classes=f"panel panel{suffix}"):
            yield Static(title, classes=f"panel-title panel-title{suffix}")
            with Vertical(classes="panel-body"):
                for widget in widgets:
                    yield widget

    def on_mount(self) -> None:
        """Land the cursor on the step's own first field rather than
        making the user Tab to it. A subclass that overrides on_mount
        (network.py's connectivity check, for instance) must call
        super().on_mount() itself to keep this."""
        self._focus_first_field()

    def _focus_first_field(self) -> None:
        for widget in self.query_one("#wizard-body").query("*"):
            if widget.can_focus:
                widget.focus()
                return
        self.query_one("#wizard-next").focus()

    def set_error(self, message: str, focus: str | None = None) -> None:
        """Show a validation error. Pass the CSS selector of the field it's
        actually about via `focus` — the console's scrollbar renders using
        block-element glyphs the console font doesn't have, so a step
        taller than the screen gives no visible cue that there's more to
        scroll to. Bringing the actual problem field into view and focusing
        it means the user is never stuck looking at a screen that hides
        the thing they need to fix."""
        self.query_one("#wizard-error", Static).update(message)
        if focus is not None:
            widget = self.query_one(focus)
            widget.scroll_visible(animate=False)
            widget.focus()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "wizard-next":
            if self.on_next() is not False:
                self.app.wizard_advance()
        elif event.button.id == "wizard-back":
            self.action_back()

    def action_back(self) -> None:
        self.on_back()
        self.app.wizard_back()

    def on_next(self) -> bool | None:
        """Validate/commit this step's answers into self.app.state. Return
        False to block advancing (call self.set_error first)."""
        return True

    def on_back(self) -> None:
        """Called before navigating back, for any cleanup a step needs."""
        return None
