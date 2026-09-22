"""Filesystem/system probes the wizard needs: where gisnix lives on this
ISO, what hosts it already knows about, what disks are attached, and small
subprocess helpers shared by several steps."""

from __future__ import annotations

import json
import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

from .branding import find_gisnix_root

GISNIX_ROOT = find_gisnix_root()

#: Set by `--mock` / GISNIX_INSTALLER_MOCK=1 (see __main__.py). Swaps every
#: real-system probe and the actual disko/nixos-install run for fakes, so
#: the wizard can be driven end-to-end in an ordinary terminal — no VM, no
#: root, no disk at risk — for fast iteration on the screens themselves.
MOCK = os.environ.get("GISNIX_INSTALLER_MOCK") == "1"


@dataclass
class ExistingHost:
    name: str
    description: str


def existing_hosts() -> list[ExistingHost]:
    """Host profiles already checked into this gisnix (or its downstream
    layer) — offered as "install this machine's known profile" instead of
    starting from scratch."""
    if GISNIX_ROOT is None:
        return []
    hosts_dir = GISNIX_ROOT / "hosts"
    if not hosts_dir.is_dir():
        return []
    try:
        fleet = json.loads(
            subprocess.run(
                ["nix-instantiate", "--eval", "--strict", "--json", str(hosts_dir / "fleet.nix")],
                capture_output=True,
                text=True,
                check=True,
                timeout=15,
            ).stdout
        )
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired, ValueError):
        fleet = {"hosts": {}}

    out = []
    for entry in sorted(hosts_dir.iterdir()):
        if not entry.is_dir() or not (entry / "config.nix").exists():
            continue
        meta = fleet.get("hosts", {}).get(entry.name, {})
        out.append(ExistingHost(entry.name, meta.get("description", "")))
    return out


@dataclass
class Disk:
    device: str
    size_bytes: int
    size_human: str
    model: str


#: Fake disks for --mock: two sizes, so single- and multi-disk storage
#: modes both have something plausible to pick from.
_MOCK_DISKS = [
    Disk(device="/dev/vda", size_bytes=80 * 1024**3, size_human="80.0GB", model="QEMU HARDDISK (mock)"),
    Disk(device="/dev/vdb", size_bytes=80 * 1024**3, size_human="80.0GB", model="QEMU HARDDISK (mock)"),
    Disk(device="/dev/vdc", size_bytes=40 * 1024**3, size_human="40.0GB", model="QEMU HARDDISK (mock)"),
]


def list_disks() -> list[Disk]:
    """Whole-disk block devices (no partitions, no loop/rom devices) via
    lsblk — the installer only ever offers to partition an entire disk."""
    if MOCK:
        return list(_MOCK_DISKS)
    try:
        out = subprocess.run(
            ["lsblk", "-J", "-b", "-o", "NAME,TYPE,SIZE,MODEL"],
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        )
        data = json.loads(out.stdout)
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired, ValueError):
        return []

    disks = []
    for dev in data.get("blockdevices", []):
        if dev.get("type") != "disk":
            continue
        size = int(dev.get("size") or 0)
        disks.append(
            Disk(
                device=f"/dev/{dev['name']}",
                size_bytes=size,
                size_human=_human_size(size),
                model=(dev.get("model") or "").strip(),
            )
        )
    return disks


def _human_size(nbytes: int) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if nbytes < 1024 or unit == "TB":
            return f"{nbytes:.0f}{unit}" if unit == "B" else f"{nbytes / 1024:.1f}{unit}"
        nbytes /= 1024
    return f"{nbytes}B"


def network_is_up() -> bool:
    if MOCK:
        return True
    try:
        subprocess.run(
            ["curl", "-fsS", "--max-time", "5", "-o", "/dev/null", "https://cache.nixos.org"],
            check=True,
            timeout=8,
        )
        return True
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return False


class GitHubKeysError(Exception):
    """Raised by fetch_github_keys with a message fit to show the user."""


def fetch_github_keys(username: str) -> list[str]:
    """The public keys GitHub publishes for this user, no auth needed —
    https://github.com/<username>.keys is the same plain-text list GitHub's
    own docs point people at for `ssh-copy-id`. Same trick tuinix's
    installer used it for: typing a public key into a wizard by hand is
    unreliable, and there's usually no clipboard to paste one from on a
    live ISO either."""
    if MOCK:
        return [f"ssh-ed25519 AAAAMOCKMOCKMOCKMOCKMOCKMOCK {username}@github"]
    try:
        proc = subprocess.run(
            ["curl", "-fsS", "--max-time", "10", f"https://github.com/{username}.keys"],
            capture_output=True,
            text=True,
            timeout=15,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise GitHubKeysError(f"could not reach GitHub ({exc}).") from exc
    if proc.returncode != 0:
        raise GitHubKeysError(f"GitHub user {username!r} not found, or GitHub is unreachable.")
    keys = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
    if not keys:
        raise GitHubKeysError(f"GitHub user {username!r} has no public keys listed.")
    return keys


_VALID_HOSTNAME = re.compile(r"^[a-z][a-z0-9-]{0,62}$")
_VALID_USERNAME = re.compile(r"^[a-z_][a-z0-9_-]{0,31}$")


def valid_hostname(name: str) -> bool:
    return bool(_VALID_HOSTNAME.match(name))


def valid_username(name: str) -> bool:
    return bool(_VALID_USERNAME.match(name))


def hash_password(password: str) -> str:
    """SHA-512 crypt hash via mkpasswd, for hashedPassword — a plaintext
    password is never written to any generated file.

    In --mock, a missing mkpasswd (e.g. running straight from a plain
    devShell rather than the packaged installer) gets an obviously-fake
    placeholder instead of a real hash — good enough to exercise the
    wizard and inspect the generated files, never used for a real install
    (a real MOCK never writes to /mnt or calls nixos-install)."""
    try:
        out = subprocess.run(
            ["mkpasswd", "-m", "sha-512", "--stdin"],
            input=password,
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        )
        return out.stdout.strip()
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        if MOCK:
            return "!MOCK-HASH-mkpasswd-not-on-PATH!"
        raise
