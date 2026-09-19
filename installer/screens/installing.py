from __future__ import annotations

from textual import work
from textual.containers import Container
from textual.screen import Screen
from textual.widgets import Button, Footer, Header, RichLog, Static

from ..installer_run import run_install


class InstallingScreen(Screen):
    """No Back/Next bar: once this screen is up, the disk is being
    partitioned. There is nothing safe to go back to."""

    CSS = """
    InstallingScreen { align: center middle; }
    #install-card { width: 100%; height: 100%; border: solid $primary; padding: 0 1 1 1; }
    #install-title {
        background: $primary;
        color: $text;
        text-style: bold;
        text-align: center;
        height: 1;
        margin: 0 0 1 0;
    }
    #install-log { height: 1fr; border: solid $secondary; }
    #install-buttons { dock: bottom; height: 3; align: right middle; background: $surface; }
    """

    def compose(self):
        yield Header(show_clock=True)
        with Container(id="install-card"):
            yield Static("Installing gisnix", id="install-title")
            yield RichLog(id="install-log", wrap=True, highlight=False, markup=False)
            with Container(id="install-buttons"):
                yield Button("Continue", id="install-continue", variant="primary", disabled=True)
        yield Footer()

    def on_mount(self) -> None:
        self.run_install_worker()

    @work(thread=True)
    def run_install_worker(self) -> None:
        log = self.query_one("#install-log", RichLog)
        try:
            for line in run_install(self.app.state):
                self.app.call_from_thread(log.write, line)
        except Exception as exc:  # noqa: BLE001 — surfaced to the operator, not swallowed
            self.app.call_from_thread(log.write, f"\n INSTALL FAILED: {exc}\n")
            self.app.call_from_thread(log.write, "See the log above for where it stopped.")
            return
        self.app.call_from_thread(self._on_success)

    def _on_success(self) -> None:
        self.query_one("#install-continue", Button).disabled = False

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "install-continue":
            self.app.wizard_advance()
