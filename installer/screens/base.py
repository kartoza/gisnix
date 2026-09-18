"""Shared shape for every wizard step: a title, a body the subclass fills
in, and a button bar pinned to the bottom — Back/Cancel on the left, the
step's primary action on the right. Tab cycles focus; Enter activates
whichever button is focused. Mirrors the navigation tuinix's installer
established (see its SPECIFICATION.md) — proven, so kept rather than
reinvented.
"""

from __future__ import annotations

from textual.containers import Container, Horizontal
from textual.screen import Screen
from textual.widgets import Button, Footer, Static


class WizardScreen(Screen):
    """Subclass, override `body()` for the step's own widgets and
    `on_next()`/`on_back()` for what Continue/Back should do. Return False
    from `on_next()` to stay on the screen (e.g. validation failed — show
    the error via `self.set_error(...)` first)."""

    BINDINGS = [("escape", "back", "Back")]

    CSS = """
    WizardScreen {
        align: center middle;
    }
    #wizard-card {
        width: 90%;
        max-width: 76;
        height: auto;
        max-height: 90%;
        border: round $primary;
        padding: 1 2;
    }
    #wizard-title {
        text-style: bold;
        color: $primary;
        padding-bottom: 1;
    }
    #wizard-body {
        height: auto;
        padding: 1 0;
    }
    #wizard-error {
        color: $error;
        height: auto;
        padding: 0 0 1 0;
    }
    #wizard-buttons {
        height: 3;
        align: right middle;
    }
    #wizard-buttons Button {
        margin-left: 1;
    }
    #wizard-back {
        dock: left;
    }
    """

    def __init__(self, title: str, next_label: str = "Next") -> None:
        super().__init__()
        self._title = title
        self._next_label = next_label

    def compose(self):
        with Container(id="wizard-card"):
            yield Static(self._title, id="wizard-title")
            yield Static("", id="wizard-error")
            with Container(id="wizard-body"):
                yield from self.body()
            with Horizontal(id="wizard-buttons"):
                yield Button("Back", id="wizard-back")
                yield Button(self._next_label, id="wizard-next", variant="primary")
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
