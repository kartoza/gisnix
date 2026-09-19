"""The package-selection step. Used to open `gisnix configure`'s own bundle
chooser (utils/lib/configure_tui.py) in-process via `self.app.suspend()` —
but that chooser is itself a Textual App, and `App.run()` calls
`asyncio.run()` internally, which cannot nest inside the installer's own
already-running event loop ("asyncio.run() cannot be called from a running
event loop"). Rather than shelling the picker out to a subprocess to dodge
that, this step just confirms the defaults and moves on; the exact same
picker is one `gisnix configure` away once the machine is up.
"""

from __future__ import annotations

from textual.widgets import Static

from ..state import DEFAULT_BUNDLES
from .base import WizardScreen


class BundlesScreen(WizardScreen):
    def __init__(self) -> None:
        super().__init__("Software", next_label="Continue")

    def body(self):
        yield Static(
            "Installing with the default bundles:\n\n"
            + "\n".join(f"  • {name}" for name in sorted(DEFAULT_BUNDLES))
            + "\n\n"
            "That's a minimal base system plus a minimal COSMIC desktop. "
            "Once you're booted in, run `gisnix configure` from "
            "~/nixos-config to add anything else — the same bundle picker, "
            "running on the installed system rather than the installer.",
            id="bundles-summary",
        )

    def on_next(self) -> bool | None:
        self.app.state.bundles = set(DEFAULT_BUNDLES)
        return True
