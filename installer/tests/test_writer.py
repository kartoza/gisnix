"""installer/writer.py — the generated Nix files. Exists because of a
real incident: render_disks_nix's zfs-multi branch joined device paths
with ", " into `[ "a", "b" ]`, which is not valid Nix list syntax (Nix
lists are space-separated: `[ "a" "b" ]`) — would have broken every
multi-disk install at flake evaluation time, before disko ever ran."""

from __future__ import annotations

import shutil
import subprocess

import pytest

from installer.state import (
    STORAGE_XFS_SINGLE,
    STORAGE_ZFS_ENCRYPTED_SINGLE,
    STORAGE_ZFS_MULTI,
    InstallState,
)
from installer.writer import render_disks_nix

NIX_INSTANTIATE = shutil.which("nix-instantiate")
requires_nix = pytest.mark.skipif(NIX_INSTANTIATE is None, reason="nix-instantiate not on PATH")


def _multi_disk_state(devices, raid_mode="raidz") -> InstallState:
    state = InstallState()
    state.storage_mode = STORAGE_ZFS_MULTI
    state.disks = devices
    state.disk_sizes = {d: 1000 * 1024**3 for d in devices}
    state.zfs_raid_mode = raid_mode
    state.zfs_multi_encrypted = True
    return state


def test_zfs_multi_device_list_is_space_separated_not_comma_separated():
    state = _multi_disk_state(["/dev/nvme0n1", "/dev/nvme1n1", "/dev/nvme2n1"])
    out = render_disks_nix(state)
    assert 'devices = [ "/dev/nvme0n1" "/dev/nvme1n1" "/dev/nvme2n1" ];' in out
    assert '", "' not in out, "comma-separated Nix list — invalid syntax, breaks every multi-disk install"


@requires_nix
def test_zfs_multi_output_parses_as_nix(tmp_path):
    state = _multi_disk_state(["/dev/nvme0n1", "/dev/nvme1n1", "/dev/nvme2n1"])
    _assert_parses(render_disks_nix(state), tmp_path)


@requires_nix
def test_zfs_encrypted_single_output_parses_as_nix(tmp_path):
    state = InstallState()
    state.storage_mode = STORAGE_ZFS_ENCRYPTED_SINGLE
    state.disks = ["/dev/sda"]
    state.disk_sizes = {"/dev/sda": 250 * 1024**3}
    _assert_parses(render_disks_nix(state), tmp_path)


@requires_nix
def test_xfs_single_output_parses_as_nix(tmp_path):
    state = InstallState()
    state.storage_mode = STORAGE_XFS_SINGLE
    state.disks = ["/dev/sda"]
    _assert_parses(render_disks_nix(state), tmp_path)


def _assert_parses(nix_source: str, tmp_path) -> None:
    path = tmp_path / "disks.nix"
    path.write_text(nix_source)
    result = subprocess.run(
        [NIX_INSTANTIATE, "--parse", str(path)], capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f"invalid Nix syntax:\n{nix_source}\n\n{result.stderr}"


def test_zfs_encrypted_single_quotas_come_from_the_real_disk_size():
    state = InstallState()
    state.storage_mode = STORAGE_ZFS_ENCRYPTED_SINGLE
    state.disks = ["/dev/sda"]
    state.disk_sizes = {"/dev/sda": 250 * 1024**3}
    out = render_disks_nix(state)
    # A real 250G disk must not still carry the old flat 20G default —
    # that fixed number is exactly the bug this whole module replaced.
    assert 'nixQuota = "20G";' not in out
    for field in ("rootQuota", "nixQuota", "homeQuota", "overflowQuota"):
        assert f'{field} = "' in out
