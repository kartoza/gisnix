"""Shared shape for every wizard step: a title, a body the subclass fills
in, and a button bar pinned to the bottom — Back/Cancel on the left, the
step's primary action on the right. Tab cycles focus; Enter activates
whichever button is focused. Mirrors the navigation tuinix's installer
established (see its SPECIFICATION.md) — proven, so kept rather than
reinvented.
"""

from __future__ import annotations

from textual.containers import Container, Horizontal, VerticalScroll
from textual.screen import Screen
from textual.widgets import Button, Footer, Header, Static


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
    #wizard-title {
        background: $primary;
        color: $text;
        text-style: bold;
        text-align: center;
        height: 1;
        margin: 0 0 1 0;
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
    """

    def __init__(self, title: str, next_label: str = "Next", next_variant: str = "primary") -> None:
        super().__init__()
        self._title = title
        self._next_label = next_label
        self._next_variant = next_variant

    def compose(self):
        yield Header(show_clock=True)
        with Container(id="wizard-card"):
            yield Static(self._title, id="wizard-title")
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

    def set_error(self, message: str) -> None:
        self.query_one("#wizard-error", Static).update(message)

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
