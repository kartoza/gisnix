from __future__ import annotations

import json

from textual.containers import VerticalGroup
from textual.widgets import Input, Label, RadioButton, RadioSet, Select

from ..repo import GISNIX_ROOT, valid_hostname
from .base import WizardScreen


def _load_locales() -> list[tuple[str, str]]:
    """Every locale gisnix ships, read from software/locale/locales.json —
    the same manifest utils/gen-locales.py builds the modules from, so the
    installer menu and the bundle registry can't drift. Select() options
    are (label, value) pairs; the value is the `locale = "<code>";` string.
    """
    fallback = [("South Africa — English", "za-en")]
    if GISNIX_ROOT is None:
        return fallback
    manifest = GISNIX_ROOT / "software" / "locale" / "locales.json"
    try:
        entries = json.loads(manifest.read_text())
    except (OSError, ValueError):
        return fallback
    return [(e["label"], e["code"]) for e in sorted(entries, key=lambda e: e["label"])]


#: (label, code) for every shipped locale, default first.
LOCALES = _load_locales()


class HostDetailsScreen(WizardScreen):
    def __init__(self) -> None:
        super().__init__("Name this machine", next_label="Continue")

    def body(self):
        with VerticalGroup():
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
                "letters, digits, and hyphens.",
                focus="#hostname-input",
            )
            return False
        self.app.state.hostname = hostname
        self.app.state.locale = self.query_one("#locale-select", Select).value
        theme = self.query_one("#boot-theme", RadioSet).pressed_button
        self.app.state.boot_theme = "qgis" if theme and theme.id == "theme-qgis" else "kartoza"
        return True
