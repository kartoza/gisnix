"""The gisnix installer — a Kartoza-branded Textual wizard.

Steps are pushed as Screens onto a stack; Next pushes the next step, Back
pops. The step SEQUENCE is dynamic (new-host vs existing-host-profile
branch differently), so it is decided one step at a time by
`next_screen()` rather than fixed up front.
"""

from __future__ import annotations

from textual.app import App

from . import branding
from .repo import MOCK
from .state import InstallState


class InstallerApp(App):
    """CSS variables aren't native Textual — colors are interpolated
    directly from the Kartoza palette (branding.textual_css_vars())."""

    TITLE = "gisnix installer" + (" [MOCK]" if MOCK else "")

    # App-level CSS applies across every screen.
    #
    # Button's built-in border style is "tall" — a 3D-embossed look built
    # from eighth-block characters (▔▁▊▎), a different Unicode range from
    # box-drawing. The console font has box-drawing coverage but not that
    # one, which is exactly the garbage that showed up under every button.
    # Every rule below re-borders with "solid" (┌─┐│└┘ — the basic
    # box-drawing set the font does carry) with !important, because
    # Button's own DEFAULT_CSS nests variant/hover/focus rules deeply
    # enough that a plain override loses to it otherwise.
    #
    # The built-in focus style is a 5% background tint — meant for a real
    # terminal with full colour depth, invisible on a virtual console.
    # `!important` bold-reverse is unmissable regardless of colour support.
    CSS = """
    Button {
        border: solid $surface-lighten-2 !important;
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
    Button:focus {
        border: solid $accent !important;
        background: $accent 35% !important;
        text-style: bold reverse !important;
    }
    *:focus {
        text-style: bold reverse;
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
        return registry[step]()

    def _next_step_name(self, current: str) -> str | None:
        order_new = [
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
        order_existing = [
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
        order = order_existing if self.state.use_existing_host else order_new
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
