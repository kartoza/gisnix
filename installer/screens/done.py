from __future__ import annotations

from textual.containers import Container
from textual.screen import Screen
from textual.widgets import Button, Static


class DoneScreen(Screen):
    CSS = """
    DoneScreen { align: center middle; }
    #done-card { width: 100%; height: 100%; border: round $primary; padding: 1 2; }
    #done-title { text-style: bold; color: $primary; height: auto; padding-bottom: 1; }
    #done-buttons { dock: bottom; height: 3; align: right middle; background: $surface; }
    """

    def compose(self):
        state = self.app.state
        with Container(id="done-card"):
            yield Static("gisnix is installed", id="done-title")
            yield Static(
                f"1. Remove the USB drive and reboot.\n"
                f"2. If you chose ZFS encryption, enter the passphrase at the prompt.\n"
                f"3. Log in as {state.username}.\n\n"
                f"~/nixos-config is the single source of truth from here — "
                f"gisnix configure, gisnix update, gisnix bundles all work exactly as on any "
                f"other gisnix machine."
            )
            with Container(id="done-buttons"):
                yield Button("Finish", id="done-finish", variant="primary")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "done-finish":
            self.app.exit()
