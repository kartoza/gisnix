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

#: Stack order, top (most user-visible) to bottom (foundation) — rendered
#: as a card each, in that order. Must stay the same five names as
#: state.DEFAULT_BUNDLES; deliberately hardcoded rather than derived from
#: that set, since a set has no order of its own to render a stack from.
#: Tone follows the same split: the two desktop-facing layers get the
#: accent (gold) card, the three plumbing layers underneath stay in the
#: calmer secondary (blue) card.
_STACK = [
    ("desktop-browsers", "accent"),
    ("desktop-environments-cosmic", "accent"),
    ("services-device-input-kanata", "secondary"),
    ("services-system", "secondary"),
    ("base", "secondary"),
]


class BundlesScreen(WizardScreen):
    def __init__(self) -> None:
        super().__init__("Software", next_label="Continue")

    def body(self):
        yield Static(
            "This is a minimal system with COSMIC desktop and browsers. Once "
            "you reboot into the system post install, you can cd into "
            "~/nixos-config and run 'gisnix configure' to add more bundles "
            "of software to your system."
        )
        # A bare colour bar per bundle, not a full panel() card — no
        # border, no body, no description, just the name. Reuses
        # panel-title's own CSS classes directly (background/bold/
        # height:1) so the stack still reads by colour, but fits on one
        # screen instead of five bordered boxes with paragraph bodies.
        for name, tone in _STACK:
            suffix = f"-{tone}" if tone != "secondary" else ""
            yield Static(name, classes=f"panel-title panel-title{suffix}")

    def on_next(self) -> bool | None:
        self.app.state.bundles = set(DEFAULT_BUNDLES)
        return True
