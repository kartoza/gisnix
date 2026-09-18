from __future__ import annotations

from textual.widgets import Static

from .base import WizardScreen


class WelcomeScreen(WizardScreen):
    """The Kartoza logo itself is shown by the launch wrapper (chafa,
    printed to the raw terminal before this app starts) rather than inside
    a widget here — raw ANSI art fed into a Textual Static wraps badly
    (each "pixel" is many escape-code characters, so a normal word-wrapping
    widget can turn a 25-line image into hundreds of wrapped rows)."""

    def __init__(self) -> None:
        super().__init__("Welcome to gisnix", next_label="Get started")

    def body(self):
        yield Static(
            "A reproducible NixOS distribution for GIS workstations.\n\n"
            "This wizard will partition a disk, create your account, and "
            "install a minimal base system with a minimal COSMIC desktop by "
            "default — pick more software later.\n\n"
            "[b]This can erase a disk.[/b] Nothing is written until you "
            "confirm at the end.",
        )

    def on_back(self) -> None:
        self.app.exit()
