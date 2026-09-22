from __future__ import annotations

from textual import work
from textual.containers import Container
from textual.screen import Screen
from textual.widgets import Button, Footer, Header, RichLog, Static

from ..installer_run import MOUNT_ROOT, run_install

#: Where the running install log gets teed to, once /mnt is the real
#: target root rather than an empty directory on the live ISO — see
#: run_install_worker's own comment. Survives a failed install (and a
#: reboot, mounted read-only from another system) instead of needing a
#: phone photo of the screen to diagnose.
INSTALL_LOG_PATH = MOUNT_ROOT / "gisnix-install.log"


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
        # Buffered until /mnt is a real mountpoint (disko hasn't run yet at
        # the start of install, so writing there earlier would land on the
        # live ISO's throwaway root and vanish the moment disko mounts the
        # target over it) — then flushed and appended to live, so a failure
        # partway through nixos-install still leaves a file on the target
        # disk, not just whatever survived on screen.
        lines: list[str] = []
        log_fh = None

        def record(line: str) -> None:
            nonlocal log_fh
            lines.append(line)
            if log_fh is None:
                if not MOUNT_ROOT.is_mount():
                    return
                try:
                    log_fh = INSTALL_LOG_PATH.open("w")
                    log_fh.write("\n".join(lines) + "\n")
                    log_fh.flush()
                except OSError:
                    log_fh = None
                return
            try:
                log_fh.write(line + "\n")
                log_fh.flush()
            except OSError:
                pass

        try:
            for line in run_install(self.app.state):
                record(line)
                self.app.call_from_thread(log.write, line)
        except Exception as exc:  # noqa: BLE001 — surfaced to the operator, not swallowed
            record(f"\nINSTALL FAILED: {exc}")
            self.app.call_from_thread(log.write, f"\n INSTALL FAILED: {exc}\n")
            if log_fh is not None:
                self.app.call_from_thread(
                    log.write, f"See the log above for where it stopped — full log saved to {INSTALL_LOG_PATH}."
                )
            else:
                self.app.call_from_thread(log.write, "See the log above for where it stopped.")
            return
        finally:
            if log_fh is not None:
                log_fh.close()
        self.app.call_from_thread(self._on_success)

    def _on_success(self) -> None:
        self.query_one("#install-continue", Button).disabled = False

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "install-continue":
            self.app.wizard_advance()
