"""The gisnix installer — a Kartoza-branded Textual wizard.

Steps are pushed as Screens onto a stack; Next pushes the next step, Back
pops. The step SEQUENCE is dynamic (new-host vs existing-host-profile
branch differently), so it is decided one step at a time by
`next_screen()` rather than fixed up front.
"""

from __future__ import annotations

from textual.app import App
from textual.widgets._toggle_button import ToggleButton  # noqa: PLC2701 — see comment below

from . import branding
from .repo import MOCK
from .state import InstallState

# RadioButton, Checkbox, AND SelectionList (which reads these directly off
# ToggleButton rather than off its own class — checked its source) all draw
# their on/off marker as BUTTON_LEFT + (inner glyph) + BUTTON_RIGHT. The
# inner glyphs themselves are fine (RadioButton's "●" and Checkbox's "X"
# are both ordinary, widely-supported characters) — it's the shared
# wrapper, "▐"/"▌" (block elements, not box-drawing), that the console
# font doesn't have. Reaching the private module is unavoidable: it's the
# one place all three widgets actually read this from.
ToggleButton.BUTTON_LEFT = "("
ToggleButton.BUTTON_RIGHT = ")"


class InstallerApp(App):
    """CSS variables aren't native Textual — colors are interpolated
    directly from the Kartoza palette (branding.textual_css_vars())."""

    TITLE = "gisnix installer" + (" [MOCK]" if MOCK else "")

    # Textual's own ctrl+p command palette (theme switcher, etc.) has
    # nothing to do with this wizard and its footer hint/corner affordance
    # is one more thing to explain to someone who just wants to install a
    # machine — this is a fixed-purpose flow, not a general Textual app.
    ENABLE_COMMAND_PALETTE = False

    # App-level CSS applies across every screen.
    #
    # Button, Input, ToggleButton (the base class behind RadioButton and
    # Checkbox), OptionList (the base class behind SelectionList), and
    # Select's own closed-state display ALL default to a "tall" border —
    # a 3D-embossed look built from eighth-block characters (▔▁▊▎), a
    # different Unicode range from box-drawing. The console font has
    # box-drawing coverage but not that one, which is exactly the garbage
    # that showed up under buttons, around the focused password field,
    # around every radio button, and around the disk list and dropdowns.
    # Every rule below re-borders with "solid" (┌─┐│└┘ — the basic
    # box-drawing set the font does carry) with !important, because each
    # widget's own DEFAULT_CSS nests variant/hover/focus rules deeply
    # enough that a plain override loses to it otherwise.
    #
    # The built-in focus style is a 5% background tint — meant for a real
    # terminal with full colour depth, invisible on a virtual console. The
    # first fix for that was `text-style: bold reverse`, which is unmissable
    # but wrong: `reverse` swaps foreground/background at render time, and
    # Textual's default foreground on a dark theme is near-white — so every
    # focused widget rendered as a stark white block with dark text, on both
    # the console AND a real terminal. The accent tint below is already the
    # unmissable-on-a-console fix; `bold` alone is enough extra emphasis on
    # top of it, no inversion needed.
    CSS = """
    Button, Input, ToggleButton, OptionList, SelectCurrent, RadioSet, TextArea {
        border: solid $surface-lighten-2 !important;
    }
    Button {
        min-width: 16;
    }
    Button:hover {
        border: solid $secondary !important;
    }
    Button.-primary, Button.-success {
        border: solid $primary !important;
    }
    Button.-warning {
        border: solid $warning !important;
    }
    Button.-error {
        border: solid $error !important;
    }
    Input.-invalid {
        border: solid $error !important;
    }
    Button:focus, Input:focus, ToggleButton:focus, OptionList:focus, SelectCurrent:focus,
    RadioSet:focus, TextArea:focus {
        border: solid $accent !important;
        background: $accent 45% !important;
        text-style: bold !important;
    }
    Input.-invalid:focus {
        border: solid $error !important;
        background: $error 45% !important;
    }
    *:focus {
        text-style: bold;
    }
    """

    def __init__(self) -> None:
        super().__init__()
        self.state = InstallState()
        self._history: list[str] = ["welcome"]

    def get_css_variables(self) -> dict[str, str]:
        variables = super().get_css_variables()
        variables.update(branding.textual_css_vars())
        return variables

    def on_mount(self) -> None:
        self.push_screen(self._make("welcome"))

    def _make(self, step: str):
        from .screens import (
            bundles,
            confirm,
            done,
            existing_host,
            host_details,
            host_mode,
            installing,
            network,
            storage,
            user,
            welcome,
        )

        registry = {
            "welcome": welcome.WelcomeScreen,
            "network": network.NetworkScreen,
            "host_mode": host_mode.HostModeScreen,
            "existing_host": existing_host.ExistingHostScreen,
            "host_details": host_details.HostDetailsScreen,
            "user": user.UserScreen,
            "storage": storage.StorageScreen,
            "bundles": bundles.BundlesScreen,
            "confirm": confirm.ConfirmScreen,
            "installing": installing.InstallingScreen,
            "done": done.DoneScreen,
        }
        screen = registry[step]()
        order = self._current_order()
        if step in order:
            screen.set_step(order.index(step) + 1, len(order))
        return screen

    #: Two step sequences — the existing-host reinstall path skips
    #: host_details/bundles (a known profile already has both). Kept as one
    #: source of truth: _next_step_name walks it, _make numbers screens
    #: against it, so the step badge and the actual navigation can never
    #: drift out of sync with each other.
    _ORDER_NEW = [
        "welcome",
        "network",
        "host_mode",
        "host_details",
        "user",
        "storage",
        "bundles",
        "confirm",
        "installing",
        "done",
    ]
    _ORDER_EXISTING = [
        "welcome",
        "network",
        "host_mode",
        "existing_host",
        "user",
        "storage",
        "confirm",
        "installing",
        "done",
    ]

    def _current_order(self) -> list[str]:
        return self._ORDER_EXISTING if self.state.use_existing_host else self._ORDER_NEW

    def _next_step_name(self, current: str) -> str | None:
        order = self._current_order()
        try:
            i = order.index(current)
        except ValueError:
            return None
        return order[i + 1] if i + 1 < len(order) else None

    def wizard_advance(self) -> None:
        current = self._history[-1]
        nxt = self._next_step_name(current)
        if nxt is None:
            return
        self._history.append(nxt)
        self.push_screen(self._make(nxt))

    def wizard_back(self) -> None:
        if len(self._history) <= 1:
            return
        self._history.pop()
        self.pop_screen()


def main() -> None:
    InstallerApp().run()


if __name__ == "__main__":
    main()
