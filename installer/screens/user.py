from __future__ import annotations

from textual.containers import Vertical
from textual.widgets import Input, Label, TextArea

from ..repo import hash_password, valid_username
from .base import WizardScreen


class UserScreen(WizardScreen):
    def __init__(self) -> None:
        super().__init__("Create your account", next_label="Continue")

    def body(self):
        with Vertical():
            yield Label("Username")
            yield Input(placeholder="e.g. alice", id="username-input")
            yield Label("Full name (optional)")
            yield Input(placeholder="e.g. Alice Example", id="fullname-input")
            yield Label("Password")
            yield Input(password=True, id="password-input")
            yield Label("Confirm password")
            yield Input(password=True, id="password-confirm-input")
            yield Label("SSH public key(s) — optional, one per line")
            yield TextArea(id="sshkeys-input")

    def on_next(self) -> bool | None:
        username = self.query_one("#username-input", Input).value.strip().lower()
        if not valid_username(username):
            self.set_error(
                "Username must start with a letter or underscore and contain only "
                "lowercase letters, digits, hyphens, and underscores."
            )
            return False

        password = self.query_one("#password-input", Input).value
        confirm = self.query_one("#password-confirm-input", Input).value
        if not password:
            self.set_error("A password is required.")
            return False
        if password != confirm:
            self.set_error("Passwords do not match.")
            return False

        keys_text = self.query_one("#sshkeys-input", TextArea).text
        keys = [line.strip() for line in keys_text.splitlines() if line.strip()]

        state = self.app.state
        state.username = username
        state.full_name = self.query_one("#fullname-input", Input).value.strip()
        state.password_hash = hash_password(password)
        state.ssh_public_keys = keys
        return True
