#!/usr/bin/env python3
"""A Textual front end for stream-sprout — restream-to-multiple-platforms
over RTMP (see software/desktop/multimedia/obs.nix for how it's installed).

stream-sprout itself is a bash script plus ffmpeg: it listens for one RTMP
source (OBS) and tees it, unmodified, to every enabled destination in its
YAML config. It has no daemon mode, no status socket and no API — only a
config file on disk and a foreground process that logs lines like
"FFmpeg is streaming". Everything below is built on exactly those two
surfaces:

  * EDIT  reads/writes the same stream-sprout.yaml stream-sprout itself
    searches for (cwd, then $XDG_CONFIG_HOME, then /etc) — see
    find_config() — so what this app saves is what a plain `stream-sprout`
    invocation picks up.
  * RUN   launches `stream-sprout --config <path>` as a child process and
    tails its stdout. The "monitor" tab can only ever show what that log
    says: there is no per-destination health check, because ffmpeg's tee
    muxer (`onfail=ignore`) doesn't expose one. "Forwarding to" lists the
    enabled destinations from the config, not a live-measured fact per
    destination.

Quick Links are plain known URLs for the platforms stream-sprout talks to
(YouTube Studio, Twitch's dashboard) plus whatever self-hosted PeerTube /
Owncast admin URLs the operator records — there is no universal PeerTube
or Owncast URL to guess, so those start blank.
"""

from __future__ import annotations

import argparse
import os
import shutil
import signal
import subprocess
import sys
import uuid
import webbrowser
from dataclasses import dataclass, field, replace
from pathlib import Path

import yaml

from textual.app import App, ComposeResult
from textual.containers import Horizontal, VerticalScroll
from textual.coordinate import Coordinate
from textual.screen import ModalScreen
from textual.widgets import (
    Button,
    Checkbox,
    DataTable,
    Footer,
    Header,
    Input,
    Log,
    OptionList,
    Select,
    Static,
    TabbedContent,
    TabPane,
)
from textual.widgets.option_list import Option

STREAM_SPROUT_YAML = "stream-sprout.yaml"
SIDECAR_NAME = "stream-sprout-tui.json"

# Fixed RTMP ingest points, straight from stream-sprout's own
# stream-sprout.yaml.example / README. PeerTube and Owncast are
# self-hosted — there is no fixed endpoint to offer, so "custom" leaves
# rtmp_server blank for the operator to paste their own instance's URL.
KNOWN_SERVICES: dict[str, str] = {
    "twitch": "rtmp://live.twitch.tv/app/",
    "youtube": "rtmp://a.rtmp.youtube.com/live2/",
    "trovo": "rtmp://livepush.trovo.live/live/",
}

#: Select() options for the service modal. A plain list rather than built
#: from KNOWN_SERVICES, since the "custom" entry's label isn't a service
#: name and str.title()-ing it would mangle "PeerTube"/"Owncast".
PRESET_OPTIONS: list[tuple[str, str]] = [
    ("Twitch", "twitch"),
    ("YouTube", "youtube"),
    ("Trovo", "trovo"),
    ("Custom / self-hosted (PeerTube, Owncast, Kick, …)", "custom"),
]

# Real, official management pages for the platforms above. Nothing here is
# guessed: PeerTube and Owncast are self-hosted and have no such page, so
# they live only in the operator's own custom-links list (see Sidecar).
BUILTIN_LINKS: list[tuple[str, str]] = [
    ("YouTube Studio — Live dashboard", "https://studio.youtube.com/"),
    ("Twitch Creator Dashboard", "https://dashboard.twitch.tv/"),
    ("Twitch stream key & settings", "https://dashboard.twitch.tv/settings/stream"),
]


def xdg_config_home() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config"))


# ── config model ─────────────────────────────────────────────────────────


@dataclass
class Server:
    ip: str = "127.0.0.1"
    port: int = 1935
    app: str = "sprout"
    key: str = ""
    archive_stream: bool = False
    archive_path: str = "~/Streams"


@dataclass
class Service:
    name: str
    enabled: bool = True
    rtmp_server: str = ""
    key: str = ""


@dataclass
class Config:
    path: Path
    server: Server = field(default_factory=Server)
    #: insertion order is preserved and is what gets written back, so the
    #: services section doesn't reshuffle every save.
    services: dict[str, Service] = field(default_factory=dict)


def default_config_paths() -> list[Path]:
    """Same search order stream-sprout itself uses — see the script's
    `parse_yaml` call site: cwd, then XDG config, then /etc."""
    return [
        Path.cwd() / STREAM_SPROUT_YAML,
        xdg_config_home() / STREAM_SPROUT_YAML,
        Path("/etc") / STREAM_SPROUT_YAML,
    ]


def find_config(explicit: Path | None) -> Path:
    if explicit is not None:
        return explicit
    for candidate in default_config_paths():
        if candidate.exists():
            return candidate
    # Nothing exists yet — default to the XDG path; it's created on save,
    # never implicitly.
    return default_config_paths()[1]


def load_config(path: Path) -> Config:
    data: dict = {}
    if path.exists():
        data = yaml.safe_load(path.read_text()) or {}
    server_data = data.get("server") or {}
    server = Server(
        ip=str(server_data.get("ip", Server.ip)),
        port=int(server_data.get("port", Server.port)),
        app=str(server_data.get("app", Server.app)),
        key=str(server_data.get("key", "")),
        archive_stream=bool(server_data.get("archive_stream", False)),
        archive_path=str(server_data.get("archive_path", Server.archive_path)),
    )
    services = {
        name: Service(
            name=name,
            enabled=bool(sdata.get("enabled", False)),
            rtmp_server=str(sdata.get("rtmp_server", "")),
            key=str(sdata.get("key", "")),
        )
        for name, sdata in (data.get("services") or {}).items()
    }
    return Config(path=path, server=server, services=services)


def save_config(config: Config) -> None:
    payload = {
        "server": {
            "ip": config.server.ip,
            "port": config.server.port,
            "app": config.server.app,
            "key": config.server.key,
            "archive_stream": config.server.archive_stream,
            "archive_path": config.server.archive_path,
        },
        "services": {
            name: {
                "enabled": s.enabled,
                "rtmp_server": s.rtmp_server,
                "key": s.key,
            }
            for name, s in config.services.items()
        },
    }
    config.path.parent.mkdir(parents=True, exist_ok=True)
    tmp = config.path.with_suffix(config.path.suffix + ".tmp")
    tmp.write_text(yaml.safe_dump(payload, sort_keys=False))
    tmp.replace(config.path)
    # Stream keys are bearer credentials — anyone who has one can publish
    # to that channel. Not world/group-readable once this app has touched it.
    try:
        config.path.chmod(0o600)
    except OSError:
        pass


# ── sidecar: TUI-only state stream-sprout's own parser never sees ──────────
#
# Custom quick-links (self-hosted PeerTube/Owncast admin URLs) aren't part
# of stream-sprout's schema and have no business in stream-sprout.yaml —
# that file is also read by a hand-rolled sed/awk parser that only expects
# `server.*` and `services.*` keys. A sidecar keeps the two concerns apart.


def sidecar_path() -> Path:
    return xdg_config_home() / SIDECAR_NAME


def load_custom_links() -> list[tuple[str, str]]:
    import json

    path = sidecar_path()
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        return []
    return [(row["label"], row["url"]) for row in data.get("links", [])]


def save_custom_links(links: list[tuple[str, str]]) -> None:
    import json

    path = sidecar_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"links": [{"label": l, "url": u} for l, u in links]}, indent=2))


# ── modal: add / edit a service ─────────────────────────────────────────


class ServiceModal(ModalScreen[Service | None]):
    """One form for adding or editing a restream destination.

    A preset (Twitch/YouTube/Trovo) only ever fills in the name and RTMP
    URL fields when they're still empty — it never overwrites a key, since
    there is no such thing as a correct preset key to fabricate.
    """

    CSS = """
    ServiceModal {
        align: center middle;
    }
    #dialog {
        width: 70;
        height: auto;
        border: thick $accent;
        background: $surface;
        padding: 1 2;
    }
    #dialog Input, #dialog Select { margin-bottom: 1; }
    """

    def __init__(self, existing: Service | None = None) -> None:
        super().__init__()
        self.existing = existing

    def compose(self) -> ComposeResult:
        s = self.existing
        with VerticalScroll(id="dialog"):
            yield Static(
                "[bold]Edit service[/bold]" if s else "[bold]Add a restream destination[/bold]"
            )
            yield Select(
                PRESET_OPTIONS,
                prompt="preset (optional — fills in the RTMP URL)",
                id="preset",
            )
            yield Input(value=s.name if s else "", placeholder="name, e.g. twitch", id="name")
            yield Input(
                value=s.rtmp_server if s else "",
                placeholder="rtmp:// destination, e.g. rtmp://live.twitch.tv/app/",
                id="rtmp",
            )
            yield Input(
                value=s.key if s else "",
                placeholder="stream key",
                password=True,
                id="key",
            )
            yield Checkbox("enabled", value=s.enabled if s else True, id="enabled")
            with Horizontal():
                yield Button("Save", id="save", variant="success")
                yield Button("Cancel", id="cancel")

    def on_select_changed(self, event: Select.Changed) -> None:
        preset = event.value
        if preset in (Select.BLANK, "custom"):
            return
        name_in = self.query_one("#name", Input)
        rtmp_in = self.query_one("#rtmp", Input)
        if not name_in.value:
            name_in.value = str(preset)
        if not rtmp_in.value:
            rtmp_in.value = KNOWN_SERVICES.get(str(preset), "")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "cancel":
            self.dismiss(None)
            return
        name = self.query_one("#name", Input).value.strip()
        rtmp = self.query_one("#rtmp", Input).value.strip()
        key = self.query_one("#key", Input).value.strip()
        enabled = self.query_one("#enabled", Checkbox).value
        if not name:
            self.app.notify("needs a name", severity="error")
            return
        if not rtmp.startswith("rtmp://"):
            self.app.notify("destination must start with rtmp://", severity="error")
            return
        self.dismiss(Service(name=name, enabled=enabled, rtmp_server=rtmp, key=key))


class LinkModal(ModalScreen[tuple[str, str] | None]):
    """Record a self-hosted instance's admin URL (PeerTube, Owncast, …)."""

    CSS = """
    LinkModal { align: center middle; }
    #dialog {
        width: 70; height: auto; border: thick $accent;
        background: $surface; padding: 1 2;
    }
    #dialog Input { margin-bottom: 1; }
    """

    def compose(self) -> ComposeResult:
        with VerticalScroll(id="dialog"):
            yield Static("[bold]Add a quick link[/bold]")
            yield Input(placeholder="label, e.g. PeerTube — mytube.example.org", id="label")
            yield Input(placeholder="https://…", id="url")
            with Horizontal():
                yield Button("Save", id="save", variant="success")
                yield Button("Cancel", id="cancel")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "cancel":
            self.dismiss(None)
            return
        label = self.query_one("#label", Input).value.strip()
        url = self.query_one("#url", Input).value.strip()
        if not label or not (url.startswith("http://") or url.startswith("https://")):
            self.app.notify("needs a label and an http(s) URL", severity="error")
            return
        self.dismiss((label, url))


# ── main app ─────────────────────────────────────────────────────────────


class SproutApp(App):
    """gisnix restream — set up and run stream-sprout without hand-editing YAML."""

    CSS = """
    #endpoint-form Input { margin-bottom: 1; }
    #obs-hint { border: round $primary; padding: 1 2; margin-top: 1; }
    #targets { border: round $primary; padding: 1 2; margin-bottom: 1; }
    #status { padding: 0 1; margin-bottom: 1; }
    #stream-log { border: round $primary; }
    #links-list { border: round $primary; padding: 1 2; }
    """

    BINDINGS = [
        ("q", "quit", "quit"),
        ("a", "add_item", "add"),
        ("e", "edit_service", "edit service"),
        ("space", "toggle_service", "toggle"),
        ("d", "delete_item", "delete"),
        ("r", "reveal_keys", "reveal/hide keys"),
        ("ctrl+s", "save_all", "save"),
    ]

    def __init__(self, config_path: Path) -> None:
        super().__init__()
        self.config = load_config(config_path)
        self.custom_links = load_custom_links()
        self.show_keys = False
        self.process: subprocess.Popen | None = None
        self.title = "gisnix restream"
        self.sub_title = str(self.config.path)

    # ── layout ───────────────────────────────────────────────────────────

    def compose(self) -> ComposeResult:
        yield Header()
        with TabbedContent(initial="endpoint"):
            with TabPane("Local endpoint", id="endpoint"):
                with VerticalScroll(id="endpoint-form"):
                    yield Input(placeholder="listen ip (127.0.0.1 or 0.0.0.0)", id="ip")
                    yield Input(placeholder="port (1024-65535)", id="port")
                    yield Input(placeholder="app name (OBS path segment)", id="app")
                    with Horizontal():
                        yield Input(placeholder="server key (OBS stream key)", id="key")
                        yield Button("generate", id="gen-key")
                    yield Checkbox("archive the stream to disk", id="archive-stream")
                    yield Input(placeholder="archive path", id="archive-path")
                    yield Button("Save", id="save-endpoint", variant="success")
                    yield Static(id="obs-hint")
            with TabPane("Services", id="services"):
                yield DataTable(id="services-table", cursor_type="row")
                yield Static(
                    "a add · e edit · space toggle · d delete · r reveal keys · "
                    "ctrl+s save",
                    id="services-help",
                )
            with TabPane("Monitor", id="monitor"):
                yield Static(id="targets")
                yield Static(id="status")
                with Horizontal():
                    yield Button("Start", id="start-stream", variant="success")
                    yield Button("Stop", id="stop-stream", variant="error")
                yield Log(id="stream-log", highlight=True)
            with TabPane("Quick links", id="links"):
                yield OptionList(id="links-list")
                yield Static(
                    "enter opens in a browser · a adds a custom link "
                    "(e.g. a self-hosted PeerTube/Owncast admin page) · "
                    "d removes a custom one",
                    id="links-help",
                )
        yield Footer()

    def on_mount(self) -> None:
        self._fill_endpoint_form()
        self._update_obs_hint()
        table = self.query_one("#services-table", DataTable)
        table.add_columns("service", "enabled", "destination", "key")
        self._rebuild_services_table()
        self._update_targets()
        self._set_status("not running", "dim")
        self._rebuild_links()

    # ── local endpoint tab ───────────────────────────────────────────────

    def _fill_endpoint_form(self) -> None:
        s = self.config.server
        self.query_one("#ip", Input).value = s.ip
        self.query_one("#port", Input).value = str(s.port)
        self.query_one("#app", Input).value = s.app
        self.query_one("#key", Input).value = s.key
        self.query_one("#archive-stream", Checkbox).value = s.archive_stream
        self.query_one("#archive-path", Input).value = s.archive_path

    def _update_obs_hint(self) -> None:
        s = self.config.server
        self.query_one("#obs-hint", Static).update(
            "[bold]In OBS[/bold] → Settings → Stream → Service: Custom\n"
            f"  Server: [bold]rtmp://{s.ip}:{s.port}/{s.app}[/bold]\n"
            f"  Stream Key: [bold]{s.key or '(set one — generate →)'}[/bold]"
        )

    def on_button_pressed(self, event: Button.Pressed) -> None:
        handler = {
            "gen-key": self._generate_key,
            "save-endpoint": self._save_endpoint,
            "start-stream": self._start_stream,
            "stop-stream": self._stop_stream,
        }.get(event.button.id or "")
        if handler is not None:
            handler()

    def _generate_key(self) -> None:
        self.query_one("#key", Input).value = str(uuid.uuid4())

    def _save_endpoint(self) -> None:
        try:
            port = int(self.query_one("#port", Input).value)
        except ValueError:
            self.notify("port must be a number", severity="error")
            return
        if not 1024 <= port <= 65535:
            self.notify("port must be 1024-65535", severity="error")
            return
        self.config.server = Server(
            ip=self.query_one("#ip", Input).value.strip() or "127.0.0.1",
            port=port,
            app=self.query_one("#app", Input).value.strip() or "sprout",
            key=self.query_one("#key", Input).value.strip(),
            archive_stream=self.query_one("#archive-stream", Checkbox).value,
            archive_path=self.query_one("#archive-path", Input).value.strip() or "~/Streams",
        )
        save_config(self.config)
        self._update_obs_hint()
        self._update_targets()
        self.notify(f"saved {self.config.path}")

    # ── services tab ─────────────────────────────────────────────────────

    def _service_order(self) -> list[str]:
        return list(self.config.services.keys())

    def _rebuild_services_table(self) -> None:
        table = self.query_one("#services-table", DataTable)
        at = table.cursor_row
        table.clear()
        for name, s in self.config.services.items():
            key_shown = s.key if self.show_keys else ("•" * min(len(s.key), 12) or "(none)")
            table.add_row(
                name,
                "[green]on[/green]" if s.enabled else "[dim]off[/dim]",
                s.rtmp_server,
                key_shown,
                key=name,
            )
        if table.row_count and at is not None:
            table.cursor_coordinate = Coordinate(min(at, table.row_count - 1), 0)

    def _selected_service(self) -> Service | None:
        table = self.query_one("#services-table", DataTable)
        if table.cursor_row is None or not table.row_count:
            return None
        order = self._service_order()
        if not 0 <= table.cursor_row < len(order):
            return None
        return self.config.services[order[table.cursor_row]]

    def action_add_item(self) -> None:
        tab = self._active_tab()
        if tab == "services":
            self.push_screen(ServiceModal(), self._on_service_added)
        elif tab == "links":
            self.push_screen(LinkModal(), self._on_link_added)

    def _on_service_added(self, service: Service | None) -> None:
        if service is None:
            return
        self.config.services[service.name] = service
        self._rebuild_services_table()
        self._update_targets()
        self.notify(f"staged {service.name} — ctrl+s to save")

    def action_edit_service(self) -> None:
        if self._active_tab() != "services":
            return
        service = self._selected_service()
        if service is None:
            self.notify("highlight a service first", severity="warning")
            return
        old_name = service.name
        self.push_screen(
            ServiceModal(service), lambda result: self._on_service_edited(old_name, result)
        )

    def _on_service_edited(self, old_name: str, service: Service | None) -> None:
        if service is None:
            return
        # The modal lets the name itself be changed — a rename, not an add —
        # so the old key has to go or the service ends up listed twice.
        if service.name != old_name:
            self.config.services.pop(old_name, None)
        self._on_service_added(service)

    def action_toggle_service(self) -> None:
        if self._active_tab() != "services":
            return
        service = self._selected_service()
        if service is None:
            return
        self.config.services[service.name] = replace(service, enabled=not service.enabled)
        self._rebuild_services_table()
        self._update_targets()

    def action_delete_item(self) -> None:
        tab = self._active_tab()
        if tab == "services":
            service = self._selected_service()
            if service is None:
                return
            del self.config.services[service.name]
            self._rebuild_services_table()
            self._update_targets()
            self.notify(f"removed {service.name} — ctrl+s to save")
        elif tab == "links":
            self._remove_highlighted_link()

    def action_reveal_keys(self) -> None:
        if self._active_tab() != "services":
            return
        self.show_keys = not self.show_keys
        self._rebuild_services_table()

    def action_save_all(self) -> None:
        save_config(self.config)
        self.notify(f"saved {self.config.path}")

    def _active_tab(self) -> str:
        return self.query_one(TabbedContent).active

    # ── monitor tab ──────────────────────────────────────────────────────

    def _update_targets(self) -> None:
        s = self.config.server
        enabled = [name for name, svc in self.config.services.items() if svc.enabled]
        self.query_one("#targets", Static).update(
            f"[bold]Incoming (set in OBS):[/bold] rtmp://{s.ip}:{s.port}/{s.app}\n"
            f"[bold]Forwarding to:[/bold] "
            + (", ".join(enabled) if enabled else "[dim](nothing enabled)[/dim]")
        )

    def _set_status(self, text: str, colour: str) -> None:
        self.query_one("#status", Static).update(f"[{colour}]●[/{colour}] {text}")

    def _start_stream(self) -> None:
        if self.process is not None and self.process.poll() is None:
            self.notify("already running", severity="warning")
            return
        binary = shutil.which("stream-sprout")
        if binary is None:
            self.notify(
                "stream-sprout isn't on PATH — it ships with this host's "
                "multimedia bundle (pkgs.stream-sprout, see "
                "software/desktop/multimedia/obs.nix)",
                severity="error",
                timeout=10,
            )
            return
        save_config(self.config)
        log = self.query_one("#stream-log", Log)
        log.clear()
        self.process = subprocess.Popen(
            [binary, "--config", str(self.config.path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        self._set_status("starting…", "yellow")
        self.run_worker(self._pump_output, thread=True, exclusive=True, group="stream-sprout")

    def _pump_output(self) -> None:
        process = self.process
        if process is None or process.stdout is None:
            return
        for line in process.stdout:
            self.call_from_thread(self._on_log_line, line.rstrip())
        code = process.wait()
        self.call_from_thread(self._on_process_exit, code)

    def _on_log_line(self, line: str) -> None:
        self.query_one("#stream-log", Log).write_line(line)
        lowered = line.lower()
        if "is streaming" in lowered:
            self._set_status("LIVE — ffmpeg is streaming", "green")
        elif "standing-by" in lowered:
            self._set_status("standing by — waiting for OBS", "yellow")
        elif "has stopped" in lowered:
            self._set_status("stopped", "red")

    def _on_process_exit(self, code: int) -> None:
        self._set_status(f"not running (exit {code})", "dim")
        self.process = None

    def _stop_stream(self) -> None:
        if self.process is None or self.process.poll() is not None:
            self.notify("not running", severity="warning")
            return
        # SIGINT, to match the Ctrl+C stream-sprout expects for its own
        # cleanup (archive-file renaming) rather than a bare SIGTERM.
        self.process.send_signal(signal.SIGINT)

    # ── quick links tab ──────────────────────────────────────────────────
    #
    # One OptionList, not a button per row — same "a adds, d deletes, enter
    # acts" vocabulary as the services tab, and it sidesteps dynamically
    # mounting/unmounting Button widgets just to get a per-row click target.

    def _all_links(self) -> list[tuple[str, str]]:
        return BUILTIN_LINKS + self.custom_links

    def _rebuild_links(self) -> None:
        option_list = self.query_one("#links-list", OptionList)
        at = option_list.highlighted
        option_list.clear_options()
        option_list.add_options(
            Option(f"{label}\n[dim]{url}[/dim]", id=f"link:{i}")
            for i, (label, url) in enumerate(self._all_links())
        )
        if at is not None and option_list.option_count:
            option_list.highlighted = min(at, option_list.option_count - 1)

    def on_option_list_option_selected(self, event: OptionList.OptionSelected) -> None:
        if event.option_list.id != "links-list" or event.option.id is None:
            return
        self._open_link(int(event.option.id.split(":", 1)[1]))

    def _open_link(self, index: int) -> None:
        links = self._all_links()
        if not 0 <= index < len(links):
            return
        label, url = links[index]
        try:
            webbrowser.open(url)
            self.notify(f"opened {label}")
        except Exception:  # noqa: BLE001 — best-effort, headless hosts have no browser
            self.notify(f"couldn't open a browser — copy this: {url}", timeout=10)

    def _on_link_added(self, result: tuple[str, str] | None) -> None:
        if result is None:
            return
        self.custom_links.append(result)
        save_custom_links(self.custom_links)
        self._rebuild_links()

    def _remove_highlighted_link(self) -> None:
        option_list = self.query_one("#links-list", OptionList)
        if option_list.highlighted is None:
            return
        option = option_list.get_option_at_index(option_list.highlighted)
        index = int((option.id or "link:-1").split(":", 1)[1])
        custom_index = index - len(BUILTIN_LINKS)
        if custom_index < 0:
            self.notify("built-in links can't be removed", severity="warning")
            return
        label, _ = self.custom_links.pop(custom_index)
        save_custom_links(self.custom_links)
        self._rebuild_links()
        self.notify(f"removed {label}")

    # ── shutdown ─────────────────────────────────────────────────────────

    def action_quit(self) -> None:
        if self.process is not None and self.process.poll() is None:
            self.process.send_signal(signal.SIGINT)
        self.exit()


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="gisnix restream",
        description=__doc__.splitlines()[0],
    )
    parser.add_argument(
        "--config", type=Path, default=None, help="stream-sprout.yaml to edit/run"
    )
    args = parser.parse_args()
    app = SproutApp(find_config(args.config))
    try:
        app.run()
    finally:
        if app.process is not None and app.process.poll() is None:
            app.process.send_signal(signal.SIGINT)


if __name__ == "__main__":
    sys.exit(main())
