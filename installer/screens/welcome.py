from __future__ import annotations

from textual.widgets import Static

from ..repo import MOCK
from ..widgets import FontSizeSlider
from .base import WizardScreen


class WelcomeScreen(WizardScreen):
    """The full-size Kartoza logo is shown by the launch wrapper (chafa,
    printed to the raw terminal before this app starts) rather than inside
    a widget here — raw ANSI art fed into a naive Textual Static wraps badly
    (each "pixel" is many escape-code characters, so a normal word-wrapping
    widget can turn a 25-line image into hundreds of wrapped rows). The tiny
    corner badge every screen carries (base.py's title row) sidesteps that
    by parsing the ANSI through Rich's Text.from_ansi and sizing the widget
    exactly instead of letting it wrap."""

    def __init__(self) -> None:
        title = "Welcome to gisnix" + ("  [MOCK MODE]" if MOCK else "")
        super().__init__(title, next_label="Get started")

    def body(self):
        yield Static(
            "A reproducible NixOS distribution for GIS workstations.\n\n"
            "This wizard will partition a disk, create your account, and "
            "install a minimal base system with a minimal COSMIC desktop by "
            "default — pick more software later."
        )
        yield from self.panel(
            "Nothing is written until you confirm at the end",
            Static(
                "This can erase a disk. Every step up to the confirm screen "
                "is just answers being collected — disko doesn't touch a "
                "device until you type the hostname back to confirm."
                + (
                    "\n\nMOCK MODE: disks and network are faked, and the "
                    "final install step only writes files to /tmp — nothing "
                    "on this machine will be touched."
                    if MOCK
                    else ""
                )
            ),
            tone="danger",
        )
        yield FontSizeSlider(id="font-size-slider")

    def on_back(self) -> None:
        self.app.exit()
