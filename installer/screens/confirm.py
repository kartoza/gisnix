from __future__ import annotations

from textual.containers import VerticalGroup
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
        with VerticalGroup():
            yield Static("\n".join(state.summary_lines()), id="confirm-summary")
            yield Static(
                "\n[b red]THIS ERASES THE DISK(S) LISTED ABOVE.[/b red] "
                "Everything on them is gone, unrecoverably.\n"
            )
            yield Label(f'Type the hostname ("{state.hostname}") to confirm:')
            yield Input(id="confirm-input")

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
