#!/usr/bin/env python3
"""gisnix adduser — add a user account to this flake and wire it into hosts.

Mirrors the installer's user step, for a machine (or fleet) that already exists:

  - username, full name
  - a password, hashed into the user's own .nix with mkpasswd (never written
    in plaintext), exactly as the installer does it
  - SSH public keys fetched from a GitHub username (github.com/<user>.keys),
    the same trick the installer uses so nobody types a key by hand
  - which hosts get the user: each chosen host's default.nix gains an import of
    the new users/<name>.nix

Nothing is written until every file it would create or change passes
`nix-instantiate --parse`; a failure leaves the tree exactly as it was.

The bundle registry and these helpers live in gisnix's own tree (GISNIX_ROOT);
the users/ and hosts/ it edits live in the caller's flake (the cwd) — so this
runs from a downstream flake that only vendors its own hosts/ and users/, not
just from a gisnix checkout. See utils/lib/hostconfig.py for the same split.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

GISNIX_ROOT = Path(
    os.environ.get("GISNIX_ROOT", "") or Path(__file__).resolve().parent.parent
)
TARGET_ROOT = Path(os.environ.get("GISNIX_TARGET_ROOT", "") or Path.cwd())

# Reuse the installer's tested helpers rather than re-implement password hashing
# or GitHub-key fetching. installer/ is a package in gisnix's own tree.
sys.path.insert(0, str(GISNIX_ROOT))
from installer.repo import (  # noqa: E402
    GitHubKeysError,
    fetch_github_keys,
    hash_password,
    valid_username,
)

RED = "\033[0;31m"
GREEN = "\033[38;2;88;150;50m"
YELLOW = "\033[38;2;240;230;74m"
BOLD = "\033[1m"
DIM = "\033[2m"
NC = "\033[0m"


def die(msg: str) -> None:
    print(f"  {RED}✗ {msg}{NC}", file=sys.stderr)
    raise SystemExit(1)


def info(msg: str) -> None:
    print(f"  {DIM}{msg}{NC}")


def ok(msg: str) -> None:
    print(f"  {GREEN}✓ {msg}{NC}")


def gum(*args: str, stdin: str | None = None) -> str | None:
    """Run a gum widget; return the value on stdout, or None if the user
    cancelled (gum exits non-zero on Esc/Ctrl-C). The widget itself draws on
    the terminal; only its result is captured."""
    try:
        proc = subprocess.run(
            ["gum", *args],
            input=stdin,
            capture_output=True,
            text=True,
        )
    except OSError:
        die("gum is not on PATH — this command needs it for its prompts.")
    if proc.returncode != 0:
        return None
    return proc.stdout.rstrip("\n")


def hosts() -> list[str]:
    root = TARGET_ROOT / "hosts"
    if not root.is_dir():
        die("no hosts/ here — run this from your flake's own repo root.")
    return sorted(
        p.parent.name for p in root.glob("*/config.nix") if p.parent.name != ""
    )


def render_user_nix(username: str, full_name: str, password_hash: str, keys: list[str]) -> str:
    """A user module for an ADDITIONAL account — deliberately NOT the installer's
    render_user_nix, which also overrides root's password (that belongs to the
    machine's primary, install-time user, not to everyone added later)."""
    if keys:
        body = "\n".join(f'      "{k}"' for k in keys)
        keys_block = f"[\n{body}\n    ]"
    else:
        keys_block = "[ ]"
    return f"""{{ pkgs, ... }}:
{{
  users.users.{username} = {{
    isNormalUser = true;
    description = "{full_name or username}";
    extraGroups = [ "wheel" "networkmanager" "video" "input" ];
    shell = pkgs.bash;
    hashedPassword = "{password_hash}";
    openssh.authorizedKeys.keys = {keys_block};
  }};

  # kanata (services-device-input-kanata) writes remapped keystrokes through
  # /dev/uinput — this user needs the uinput group to type through it.
  users.groups.uinput.members = [ "{username}" ];
}}
"""


def parses(path: Path) -> tuple[bool, str]:
    proc = subprocess.run(
        ["nix-instantiate", "--parse", str(path)],
        capture_output=True,
        text=True,
    )
    return proc.returncode == 0, proc.stderr.strip()


def add_import_to_host(default_nix: Path, username: str) -> str:
    """Add `../../users/<name>.nix` to a host's default.nix imports, right after
    the existing users import. Returns the new file text; does NOT write it.
    Idempotent — if the user is already imported, returns the text unchanged."""
    text = default_nix.read_text()
    want = f"../../users/{username}.nix"
    if want in text:
        return text  # already imported
    lines = text.splitlines(keepends=True)
    # Insert after the last existing `../../users/*.nix` line, matching its
    # indentation; fall back to after `./hardware.nix`, then the imports open.
    anchor_idx = None
    indent = "    "
    for i, line in enumerate(lines):
        s = line.strip()
        if s.startswith("../../users/") and s.endswith(".nix"):
            anchor_idx = i
            indent = line[: len(line) - len(line.lstrip())]
        elif anchor_idx is None and s in ("./hardware.nix", "imports = ["):
            anchor_idx = i
            indent = line[: len(line) - len(line.lstrip())]
            if s == "imports = [":
                indent += "  "
    if anchor_idx is None:
        raise ValueError(f"could not find an imports list in {default_nix}")
    lines.insert(anchor_idx + 1, f"{indent}{want}\n")
    return "".join(lines)


def main() -> int:
    if not (GISNIX_ROOT / "software").is_dir():
        die("GISNIX_ROOT does not point at a gisnix tree (no software/).")

    print()
    print(f"  {BOLD}Add a user to this flake{NC}")
    print(f"  {DIM}Files are written to {TARGET_ROOT}{NC}")
    print()

    username = gum("input", "--placeholder", "username (lowercase)", "--header", "Username")
    if username is None or not username.strip():
        die("cancelled — no username given.")
    username = username.strip()
    if not valid_username(username):
        die(f"{username!r} is not a valid Linux username (a-z, 0-9, _ and -).")
    user_file = TARGET_ROOT / "users" / f"{username}.nix"
    if user_file.exists():
        die(f"users/{username}.nix already exists — pick another name or edit it directly.")

    full_name = gum("input", "--placeholder", "e.g. Ada Lovelace", "--header", "Full name") or ""
    full_name = full_name.strip()

    # SSH keys from GitHub — optional, but strongly encouraged (sshd here is
    # public-key only). Loop so a typo/unreachable name can be retried.
    keys: list[str] = []
    gh = gum("input", "--placeholder", "GitHub username (optional, for SSH keys)", "--header", "GitHub")
    while gh is not None and gh.strip():
        try:
            keys = fetch_github_keys(gh.strip())
            ok(f"fetched {len(keys)} key(s) from github.com/{gh.strip()}.keys")
            break
        except GitHubKeysError as exc:
            print(f"  {YELLOW}⚠ {exc}{NC}")
            again = gum("input", "--placeholder", "another GitHub username, or empty to skip", "--header", "GitHub")
            gh = again
    if not keys:
        info("no SSH keys added — this user can log in at the console but not over SSH until a key is added.")

    # Password, confirmed, hashed. Never stored in plaintext.
    while True:
        pw1 = gum("input", "--password", "--header", "Password")
        if pw1 is None or pw1 == "":
            die("cancelled — no password set.")
        pw2 = gum("input", "--password", "--header", "Confirm password")
        if pw2 is None:
            die("cancelled.")
        if pw1 == pw2:
            break
        print(f"  {YELLOW}⚠ passwords did not match — try again{NC}")
    password_hash = hash_password(pw1)

    # Which hosts?
    all_hosts = hosts()
    if not all_hosts:
        die("this flake has no hosts under hosts/.")
    if len(all_hosts) == 1:
        chosen = all_hosts
        info(f"one host in this flake — adding to {all_hosts[0]}")
    else:
        picked = gum("choose", "--no-limit", "--header", "Add this user to which hosts? (space to select)", *all_hosts)
        if picked is None or not picked.strip():
            die("cancelled — no hosts chosen.")
        chosen = [h for h in picked.splitlines() if h.strip()]

    # Compose every change in memory, parse-check, THEN write — so a failure
    # leaves the tree untouched.
    user_text = render_user_nix(username, full_name, password_hash, keys)
    host_edits: dict[Path, str] = {}
    for h in chosen:
        dn = TARGET_ROOT / "hosts" / h / "default.nix"
        if not dn.exists():
            die(f"hosts/{h}/default.nix not found.")
        try:
            host_edits[dn] = add_import_to_host(dn, username)
        except ValueError as exc:
            die(str(exc))

    # Parse-check the new user file (write to a temp path first).
    user_file.parent.mkdir(parents=True, exist_ok=True)
    tmp = user_file.with_suffix(".nix.tmp")
    tmp.write_text(user_text)
    good, err = parses(tmp)
    if not good:
        tmp.unlink(missing_ok=True)
        die(f"the generated users/{username}.nix does not parse:\n{err}")
    # Parse-check each host edit via its own temp file.
    for dn, new_text in host_edits.items():
        htmp = dn.with_suffix(".nix.tmp")
        htmp.write_text(new_text)
        good, err = parses(htmp)
        if not good:
            htmp.unlink(missing_ok=True)
            tmp.unlink(missing_ok=True)
            die(f"editing {dn.relative_to(TARGET_ROOT)} would break it — nothing written:\n{err}")
        htmp.unlink(missing_ok=True)

    # All checks passed — commit the writes.
    tmp.replace(user_file)
    for dn, new_text in host_edits.items():
        dn.write_text(new_text)

    print()
    ok(f"wrote users/{username}.nix")
    for h in chosen:
        ok(f"added {username} to hosts/{h}/default.nix")
    print()
    info("Apply it with:  gisnix update" + (f"   (or: gisnix update {chosen[0]})" if len(chosen) == 1 else ""))
    if not keys:
        info("Add SSH keys later by editing openssh.authorizedKeys.keys in the user file.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
