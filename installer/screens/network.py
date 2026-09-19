from __future__ import annotations

from textual.widgets import Static

from ..repo import network_is_up
from .base import WizardScreen


class NetworkScreen(WizardScreen):
    def __init__(self) -> None:
        super().__init__("Network check", next_label="Continue")

    def body(self):
        yield Static("Checking connectivity to cache.nixos.org...", id="net-status")

    def on_mount(self) -> None:
        super().on_mount()
        up = network_is_up()
        status = self.query_one("#net-status", Static)
        if up:
            status.update("[b]Connected.[/b] Packages will be fetched from the binary cache.")
        else:
            status.update(
                "[b]No connection detected.[/b] You can still continue if this is an "
                "offline install with a pre-cached closure — otherwise connect to "
                "Wi-Fi/Ethernet and come back to this step."
            )
