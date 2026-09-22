from __future__ import annotations

from textual.widgets import Input, Label, Static

from .base import WizardScreen


class ConfirmScreen(WizardScreen):
    def __init__(self) -> None:
        super().__init__(
            "Confirm — this erases the selected disk(s)",
            next_label="Install!",
            next_variant="error",
        )

    def body(self):
        state = self.app.state
        yield from self.panel(
            "This machine, as configured",
            Static("\n".join(state.summary_lines()), id="confirm-summary"),
            tone="accent",
        )
        yield from self.panel(
            "This erases the disk(s) listed above",
            Static("Everything on them is gone, unrecoverably."),
            Label(f'Type the hostname ("{state.hostname}") to confirm:'),
            Input(id="confirm-input"),
            tone="danger",
        )

    def on_next(self) -> bool | None:
        typed = self.query_one("#confirm-input", Input).value.strip()
        if typed != self.app.state.hostname:
            self.set_error(
                "That doesn't match the hostname above — nothing has been done.",
                focus="#confirm-input",
            )
            return False
        self.app.state.confirmed = True
        return True
