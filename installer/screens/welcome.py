from __future__ import annotations

from textual.widgets import Static

from ..repo import MOCK
from .base import WizardScreen


class WelcomeScreen(WizardScreen):
    """The Kartoza logo itself is shown by the launch wrapper (chafa,
    printed to the raw terminal before this app starts) rather than inside
    a widget here — raw ANSI art fed into a Textual Static wraps badly
    (each "pixel" is many escape-code characters, so a normal word-wrapping
    widget can turn a 25-line image into hundreds of wrapped rows)."""

    def __init__(self) -> None:
        title = "Welcome to gisnix" + ("  [MOCK MODE]" if MOCK else "")
        super().__init__(title, next_label="Get started")

    def body(self):
        yield Static(
            "A reproducible NixOS distribution for GIS workstations.\n\n"
            "This wizard will partition a disk, create your account, and "
            "install a minimal base system with a minimal COSMIC desktop by "
            "default — pick more software later.\n\n"
            "[b]This can erase a disk.[/b] Nothing is written until you "
            "confirm at the end."
            + (
                "\n\n[b]MOCK MODE[/b]: disks and network are faked, and the "
                "final install step only writes files to /tmp — nothing on "
                "this machine will be touched."
                if MOCK
                else ""
            ),
        )

    def on_back(self) -> None:
        self.app.exit()
