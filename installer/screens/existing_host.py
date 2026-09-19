from __future__ import annotations

from textual.widgets import OptionList
from textual.widgets.option_list import Option

from ..repo import existing_hosts
from .base import WizardScreen


class ExistingHostScreen(WizardScreen):
    def __init__(self) -> None:
        super().__init__("Choose the host profile to install", next_label="Continue")
        self._hosts = existing_hosts()

    def body(self):
        options = [
            Option(f"{h.name} — {h.description}" if h.description else h.name, id=h.name)
            for h in self._hosts
        ]
        yield OptionList(*options, id="existing-list")

    def on_next(self) -> bool | None:
        option_list = self.query_one("#existing-list", OptionList)
        if option_list.highlighted is None:
            self.set_error("Pick a host profile to continue.", focus="#existing-list")
            return False
        option = option_list.get_option_at_index(option_list.highlighted)
        self.app.state.existing_host_name = option.id
        self.app.state.hostname = option.id
        return True
