from __future__ import annotations

from textual import work
from textual.containers import Center
from textual.widgets import Static

from ..repo import network_is_up
from ..widgets import NetworkStatusCircle
from .base import WizardScreen


class NetworkScreen(WizardScreen):
    def __init__(self) -> None:
        super().__init__("Network check", next_label="Continue")

    def body(self):
        with Center():
            yield NetworkStatusCircle(id="net-circle")
        with Center():
            yield Static("Checking connectivity to cache.nixos.org...", id="net-status")
        with Center():
            yield Static(
                "Packages will be fetched from the NixOS binary cache.", id="net-caption"
            )

    def on_mount(self) -> None:
        super().on_mount()
        self._check_network()

    # thread=True: network_is_up() shells out to curl with up to an 8s
    # timeout — run inline this would freeze the whole UI (no pulse, no
    # Back/Continue) for as long as the check takes. The animation keeps
    # running regardless; report_result() just tells it what colour to
    # settle on once its own minimum hold has elapsed.
    @work(thread=True)
    def _check_network(self) -> None:
        up = network_is_up()
        self.app.call_from_thread(self._on_result, up)

    def _on_result(self, up: bool) -> None:
        self.query_one("#net-circle", NetworkStatusCircle).report_result(up)
        status = self.query_one("#net-status", Static)
        if up:
            status.update("[b]Connected.[/b]")
        else:
            status.update(
                "[b]No connection detected.[/b] The install itself needs network to "
                "fetch packages — connect to Wi-Fi/Ethernet and come back to this "
                "step before continuing."
            )
