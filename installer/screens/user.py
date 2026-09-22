from __future__ import annotations

from textual import work
from textual.containers import VerticalGroup
from textual.widgets import Input, Label, TextArea

from ..repo import GitHubKeysError, fetch_github_keys, hash_password, valid_username
from ..widgets import GitHubCheckBar, PasswordMatchBar, PasswordStrengthBar
from .base import WizardScreen

#: How often UserScreen polls #github-username-input's own has_focus to
#: notice it losing focus. A plain has_focus poll rather than an on_blur
#: override: Input's exact blur-hook signature varies enough across
#: Textual releases that a direct override risked being right on one
#: version and a TypeError on another, where has_focus is a basic,
#: stable Widget property on every version this project has run against.
#: 0.3s is imperceptible lag for "I tabbed/clicked away from this field."
_FOCUS_POLL_SECONDS = 0.3


class UserScreen(WizardScreen):
    def __init__(self) -> None:
        super().__init__("Create your account", next_label="Continue")
        self._checked_github_username: str | None = None
        self._checked_github_keys: list[str] | None = None
        self._github_input_was_focused = False

    def body(self):
        with VerticalGroup():
            yield Label("Username")
            yield Input(placeholder="e.g. alice", id="username-input")
            yield Label("Full name (optional)")
            yield Input(placeholder="e.g. Alice Example", id="fullname-input")
            yield Label("Password")
            yield Input(password=True, id="password-input")
            yield PasswordStrengthBar(id="password-strength-bar")
            yield Label("Confirm password")
            yield Input(password=True, id="password-confirm-input")
            yield PasswordMatchBar(id="password-match-bar")
            yield Label("GitHub username — imports your public key(s) automatically")
            yield Input(placeholder="e.g. octocat (optional)", id="github-username-input")
            yield GitHubCheckBar(id="github-check-bar")
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

    def on_mount(self) -> None:
        super().on_mount()
        self.set_interval(_FOCUS_POLL_SECONDS, self._poll_github_focus)

    def on_input_changed(self, event: Input.Changed) -> None:
        if event.input.id == "password-input":
            self.query_one("#password-strength-bar", PasswordStrengthBar).update_password(
                event.value
            )
            self._update_match_bar()
        elif event.input.id == "password-confirm-input":
            self._update_match_bar()

    def _update_match_bar(self) -> None:
        password = self.query_one("#password-input", Input).value
        confirm = self.query_one("#password-confirm-input", Input).value
        self.query_one("#password-match-bar", PasswordMatchBar).update_match(password, confirm)

    def _poll_github_focus(self) -> None:
        gh_input = self.query_one("#github-username-input", Input)
        is_focused = gh_input.has_focus
        if self._github_input_was_focused and not is_focused:
            self._on_github_username_blurred(gh_input.value.strip())
        self._github_input_was_focused = is_focused

    def _on_github_username_blurred(self, username: str) -> None:
        bar = self.query_one("#github-check-bar", GitHubCheckBar)
        if not username:
            self._checked_github_username = None
            self._checked_github_keys = None
            bar.reset()
            return
        if username == self._checked_github_username:
            return  # unchanged since the last check — nothing to redo
        bar.start_check()
        self._run_github_check(username)

    # thread=True: fetch_github_keys() shells out to curl with up to a
    # 15s timeout — run inline this would freeze the whole form (no
    # typing, no bar animation) for as long as the fetch takes.
    @work(thread=True)
    def _run_github_check(self, username: str) -> None:
        try:
            keys = fetch_github_keys(username)
        except GitHubKeysError:
            keys = None
        self.app.call_from_thread(self._on_github_result, username, keys)

    def _on_github_result(self, username: str, keys: list[str] | None) -> None:
        # The field may already show a different value by the time this
        # lands (edited again, or cleared, while the check was in
        # flight) — a stale result for an old value shouldn't paint the
        # bar or get treated as this username's answer.
        current = self.query_one("#github-username-input", Input).value.strip()
        if current != username:
            return
        self._checked_github_username = username
        self._checked_github_keys = keys
        self.query_one("#github-check-bar", GitHubCheckBar).report_result(keys is not None)

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
            # Reuse the blur-triggered check's result if it's still for
            # this exact value — otherwise (never blurred out, or it
            # failed and got edited back) fall back to fetching here,
            # same as before this screen grew the background check.
            if github_username == self._checked_github_username and self._checked_github_keys:
                fetched = self._checked_github_keys
            else:
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
