from __future__ import annotations

from textual import work
from textual.containers import Center
from textual.widgets import Static

from .. import branding
from ..repo import network_is_up
from ..widgets import NetworkStatusCircle
from .base import WizardScreen


class NetworkScreen(WizardScreen):
    """The circle itself carries the phase word (Preparing/Checking/
    Connected/Connection Failed — see widgets.NetworkStatusCircle), so
    there's no separate "Checking connectivity..." status line doing the
    same job in different words. #net-status stays empty on success and
    only fills in with actionable guidance on failure, where "the circle
    turned red" alone doesn't tell you what to do about it.

    No class-level CSS here — Screen.CSS is a plain class attribute, not
    something Textual merges across a subclass chain, so defining one on
    this screen would REPLACE WizardScreen's (card border, title row,
    docked button bar, all of it) instead of adding to it. See user.py's
    matching comment on its own TextArea — styling the two Statics below
    directly instead."""

    def __init__(self) -> None:
        super().__init__("Network check", next_label="Continue")

    def body(self):
        with Center():
            yield NetworkStatusCircle(id="net-circle")
        with Center():
            status = Static("", id="net-status")
            status.styles.margin = (1, 0, 0, 0)
            yield status
        with Center():
            caption = Static(
                "Packages will be fetched from the NixOS binary cache.", id="net-caption"
            )
            caption.styles.margin = (2, 0, 0, 0)
            caption.styles.color = branding.textual_css_vars()["muted"]
            yield caption

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
        if not up:
            self.query_one("#net-status", Static).update(
                "[b]No connection detected.[/b] The install itself needs network to "
                "fetch packages — connect to Wi-Fi/Ethernet and come back to this "
                "step before continuing."
            )
