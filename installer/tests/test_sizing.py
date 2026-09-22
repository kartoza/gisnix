"""installer/sizing.py — the ZFS dataset quota math. Exists because of a
real incident: every install used to ship with a hard 20G /nix quota
regardless of disk size, which a real desktop/QGIS closure could blow
straight through mid-nixos-install (see CHANGELOG 0.14.0)."""

from __future__ import annotations

import pytest

from installer import sizing

GIB = sizing.GIB


def test_quota_plan_sums_within_budget():
    disk = 250 * GIB
    plan = sizing.quota_plan(disk, esp_bytes=sizing.ESP_SIZE_BYTES, reserved_bytes=sizing.ATUIN_SIZE_BYTES)
    assert set(plan) == {"root", "nix", "home", "overflow"}
    total = sum(int(v.rstrip("G")) * GIB for v in plan.values())
    budget = disk - sizing.ESP_SIZE_BYTES - sizing.ATUIN_SIZE_BYTES - sizing.DEFAULT_HEADROOM_BYTES
    assert total <= budget, "quotas must never eat into the headroom reserve"


def test_quota_plan_every_dataset_meets_its_floor():
    disk = 250 * GIB
    plan = sizing.quota_plan(disk, esp_bytes=sizing.ESP_SIZE_BYTES, reserved_bytes=sizing.ATUIN_SIZE_BYTES)
    for name, floor in sizing.DATASET_FLOORS_BYTES.items():
        assert int(plan[name].rstrip("G")) * GIB >= floor


def test_quota_plan_raises_for_a_too_small_disk():
    with pytest.raises(sizing.DiskTooSmallError):
        sizing.quota_plan(32 * GIB, esp_bytes=sizing.ESP_SIZE_BYTES, reserved_bytes=sizing.ATUIN_SIZE_BYTES)


def test_quota_plan_accepts_the_documented_minimum_disk():
    """docs/index.md promises 48GB as the minimum — this is the number
    that promise is actually derived from; if the floors/reserves in
    sizing.py ever change, this test (and that doc line) need to change
    together, deliberately, not drift apart silently."""
    floor_total = sum(sizing.DATASET_FLOORS_BYTES.values())
    minimum_disk = floor_total + sizing.ESP_SIZE_BYTES + sizing.ATUIN_SIZE_BYTES + sizing.DEFAULT_HEADROOM_BYTES
    assert minimum_disk == 48 * GIB
    sizing.quota_plan(minimum_disk, esp_bytes=sizing.ESP_SIZE_BYTES, reserved_bytes=sizing.ATUIN_SIZE_BYTES)


@pytest.mark.parametrize("mode,parity", [("stripe", 0), ("raidz", 1), ("raidz2", 2)])
def test_multi_disk_usable_bytes_accounts_for_parity(mode, parity):
    disks = [1000 * GIB] * 4
    usable = sizing.multi_disk_usable_bytes(disks, esp_bytes=sizing.ESP_SIZE_BYTES, mode=mode)
    data_disks = len(disks) - parity
    per_disk = 1000 * GIB - sizing.ESP_SIZE_BYTES
    # 0.95 slop factor, see multi_disk_usable_bytes's own docstring.
    assert usable == int(per_disk * data_disks * 0.95)


def test_multi_disk_usable_bytes_uses_the_smallest_disk():
    disks = [500 * GIB, 2000 * GIB, 2000 * GIB]
    usable = sizing.multi_disk_usable_bytes(disks, esp_bytes=sizing.ESP_SIZE_BYTES, mode="raidz")
    per_disk = 500 * GIB - sizing.ESP_SIZE_BYTES  # the SMALLEST disk caps every disk's usable share
    assert usable == int(per_disk * 2 * 0.95)


def test_gib_str_never_rounds_down_to_zero():
    assert sizing.gib_str(0) == "1G"
    assert sizing.gib_str(GIB // 2) == "1G"
    assert sizing.gib_str(5 * GIB) == "5G"
