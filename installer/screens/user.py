from __future__ import annotations

from textual.containers import VerticalGroup
from textual.widgets import Input, Label, TextArea

from ..repo import GitHubKeysError, fetch_github_keys, hash_password, valid_username
from .base import WizardScreen


class UserScreen(WizardScreen):
    def __init__(self) -> None:
        super().__init__("Create your account", next_label="Continue")

    def body(self):
        with VerticalGroup():
            yield Label("Username")
            yield Input(placeholder="e.g. alice", id="username-input")
            yield Label("Full name (optional)")
            yield Input(placeholder="e.g. Alice Example", id="fullname-input")
            yield Label("Password")
            yield Input(password=True, id="password-input")
            yield Label("Confirm password")
            yield Input(password=True, id="password-confirm-input")
            yield Label("GitHub username — imports your public key(s) automatically")
            yield Input(placeholder="e.g. octocat (optional)", id="github-username-input")
            yield Label("Or paste key(s) directly, one per line — both are optional")
            # A class-level CSS override here would REPLACE WizardScreen's
            # CSS rather than merge with it (Screen.CSS is a plain class
            # attribute, not something Textual combines across a subclass
            # chain) — confirmed the hard way: it silently dropped the
            # card's border and the docked button bar on this screen only.
            # Styling the instance directly avoids the whole question.
            sshkeys = TextArea(id="sshkeys-input")
            sshkeys.styles.height = 5
            yield sshkeys

    def on_next(self) -> bool | None:
        username = self.query_one("#username-input", Input).value.strip().lower()
        if not valid_username(username):
            self.set_error(
                "Username must start with a letter or underscore and contain only "
                "lowercase letters, digits, hyphens, and underscores.",
                focus="#username-input",
            )
            return False

        password = self.query_one("#password-input", Input).value
        confirm = self.query_one("#password-confirm-input", Input).value
        if not password:
            self.set_error("A password is required.", focus="#password-input")
            return False
        if password != confirm:
            self.set_error("Passwords do not match.", focus="#password-confirm-input")
            return False

        keys_text = self.query_one("#sshkeys-input", TextArea).text
        keys = [line.strip() for line in keys_text.splitlines() if line.strip()]

        github_username = self.query_one("#github-username-input", Input).value.strip()
        if github_username:
            try:
                fetched = fetch_github_keys(github_username)
            except GitHubKeysError as exc:
                self.set_error(str(exc), focus="#github-username-input")
                return False
            keys = list(dict.fromkeys(keys + fetched))  # de-duplicate, keep order

        state = self.app.state
        state.username = username
        state.full_name = self.query_one("#fullname-input", Input).value.strip()
        state.password_hash = hash_password(password)
        state.ssh_public_keys = keys
        return True
