from __future__ import annotations

from textual.containers import Vertical
from textual.widgets import Input, Label, RadioButton, RadioSet, Select

from ..repo import valid_hostname
from .base import WizardScreen

#: Locale bundles gisnix ships (software/locale/locale-*.nix). Kept as a
#: short list here rather than scanning the filesystem — same set the
#: bundle registry documents.
#: Select() options are (label, value) pairs.
LOCALES = [
    ("South Africa (English)", "za-en"),
    ("Portugal (English)", "pt-en"),
    ("India (English)", "in-en"),
    ("Kenya (English)", "ke-en"),
    ("Bosnia (English)", "ba-en"),
]


class HostDetailsScreen(WizardScreen):
    def __init__(self) -> None:
        super().__init__("Name this machine", next_label="Continue")

    def body(self):
        with Vertical():
            yield Label("Hostname")
            yield Input(
                placeholder="e.g. fieldbook",
                id="hostname-input",
                value=self.app.state.hostname,
            )
            yield Label("Locale")
            yield Select(LOCALES, value="za-en", id="locale-select")
            yield Label("Boot theme")
            with RadioSet(id="boot-theme"):
                yield RadioButton("Kartoza", value=True, id="theme-kartoza")
                yield RadioButton("QGIS", id="theme-qgis")

    def on_next(self) -> bool | None:
        hostname = self.query_one("#hostname-input", Input).value.strip().lower()
        if not valid_hostname(hostname):
            self.set_error(
                "Hostname must start with a letter and contain only lowercase "
                "letters, digits, and hyphens."
            )
            return False
        self.app.state.hostname = hostname
        self.app.state.locale = self.query_one("#locale-select", Select).value
        theme = self.query_one("#boot-theme", RadioSet).pressed_button
        self.app.state.boot_theme = "qgis" if theme and theme.id == "theme-qgis" else "kartoza"
        return True
