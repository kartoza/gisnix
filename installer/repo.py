"""Filesystem/system probes the wizard needs: where gisnix lives on this
ISO, what hosts it already knows about, what disks are attached, and small
subprocess helpers shared by several steps."""

from __future__ import annotations

import json
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

from .branding import find_gisnix_root

GISNIX_ROOT = find_gisnix_root()


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
    size_human: str
    model: str


def list_disks() -> list[Disk]:
    """Whole-disk block devices (no partitions, no loop/rom devices) via
    lsblk — the installer only ever offers to partition an entire disk."""
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
    try:
        subprocess.run(
            ["curl", "-fsS", "--max-time", "5", "-o", "/dev/null", "https://cache.nixos.org"],
            check=True,
            timeout=8,
        )
        return True
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return False


_VALID_HOSTNAME = re.compile(r"^[a-z][a-z0-9-]{0,62}$")
_VALID_USERNAME = re.compile(r"^[a-z_][a-z0-9_-]{0,31}$")


def valid_hostname(name: str) -> bool:
    return bool(_VALID_HOSTNAME.match(name))


def valid_username(name: str) -> bool:
    return bool(_VALID_USERNAME.match(name))


def hash_password(password: str) -> str:
    """SHA-512 crypt hash via mkpasswd, for hashedPassword — a plaintext
    password is never written to any generated file."""
    out = subprocess.run(
        ["mkpasswd", "-m", "sha-512", "--stdin"],
        input=password,
        capture_output=True,
        text=True,
        check=True,
        timeout=10,
    )
    return out.stdout.strip()
