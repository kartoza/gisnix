from __future__ import annotations

from textual.widgets import RadioButton, RadioSet, Static

from ..repo import existing_hosts
from .base import WizardScreen


class HostModeScreen(WizardScreen):
    def __init__(self) -> None:
        super().__init__("New machine, or a known profile?", next_label="Continue")
        self._existing = existing_hosts()

    def body(self):
        with RadioSet(id="host-mode"):
            yield RadioButton("Create a new host", value=True, id="mode-new")
            if self._existing:
                yield RadioButton(
                    f"Install an existing host profile ({len(self._existing)} available)",
                    id="mode-existing",
                )
            else:
                yield Static(
                    "[dim](no existing host profiles are bundled on this image)[/dim]"
                )

    def on_next(self) -> bool | None:
        radio = self.query_one("#host-mode", RadioSet)
        pressed = radio.pressed_button
        self.app.state.use_existing_host = bool(pressed and pressed.id == "mode-existing")
        return True
