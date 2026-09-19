"""The package-selection step — the SAME bundle chooser `gisnix configure` uses
on an already-installed machine (utils/lib/configure_tui.py), suspended out
of the wizard's own Textual app and back into it when the picker exits.
One implementation, used before and after install.
"""

from __future__ import annotations

import sys

from textual.widgets import Button, Static

from ..repo import GISNIX_ROOT
from .base import WizardScreen

if GISNIX_ROOT is not None:
    sys.path.insert(0, str(GISNIX_ROOT / "utils" / "lib"))


class BundlesScreen(WizardScreen):
    def __init__(self) -> None:
        super().__init__("Choose your software", next_label="Open the bundle picker")
        self._opened = False

    def body(self):
        yield Static(
            "Default selection: minimal base system + minimal COSMIC desktop.\n\n"
            "Press the button below to open the full bundle picker (same tool as "
            "`gisnix configure`) — tick anything else you want, or leave the default "
            "and add more later.",
            id="bundles-summary",
        )

    def on_next(self) -> bool | None:
        if self._opened:
            return True
        import configure_tui  # noqa: PLC0415

        with self.app.suspend():
            result = configure_tui.choose(
                self.app.state.hostname or "new-host",
                set(self.app.state.bundles),
                {"locale": self.app.state.locale},
            )
        if result is not None:
            self.app.state.bundles = result.selected
            if "locale" in result.choices:
                self.app.state.locale = result.choices["locale"]
        self._opened = True
        self.query_one("#wizard-next", Button).label = "Continue"
        count = len(self.app.state.bundles)
        self.query_one("#bundles-summary", Static).update(
            f"{count} bundle(s) selected: {', '.join(sorted(self.app.state.bundles)) or '(none)'}\n\n"
            "Press Continue to move on."
        )
        return False  # stay on this screen so the user sees the confirmation above
