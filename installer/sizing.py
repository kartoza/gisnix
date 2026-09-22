"""ZFS dataset quota sizing for the installer's disko templates.

Both disko templates used to ship a fixed `nixQuota` ("20G" single-disk,
"300G" multi-disk) regardless of the actual disk(s) picked in the wizard,
with `root`/`home`/`overflow` left unquota'd. On a real desktop/QGIS
closure that 20G cap gets blown mid-`nixos-install`, and an unquota'd
`root`/`home` can otherwise fill the pool to 0 bytes free — which is a
much harder hole to climb out of than a single dataset hitting its quota,
since ZFS needs some free space to even delete a snapshot.

This module computes every quota-bearing dataset's size from the real
disk capacity, always leaving a fixed headroom reserve unclaimed by any
quota, so the pool never has zero elbow room to recover.
"""

from __future__ import annotations

GIB = 1024**3

#: Must match the disko templates' own espSize/atuinSize defaults
#: (templates/disko/zfs-encrypted-single.nix, zfs-multi.nix) — the
#: installer never overrides either, only the per-dataset quotas below.
ESP_SIZE_BYTES = 5 * GIB
ATUIN_SIZE_BYTES = 1 * GIB

#: Real space no dataset quota gets to claim — kept free at the pool level
#: so there's room to `zfs destroy` a snapshot, bump a quota, or just
#: breathe if every dataset fills up at once.
DEFAULT_HEADROOM_BYTES = 20 * GIB

#: Proportional split of the quota-eligible budget. `nix` gets the
#: largest share — it holds every system generation plus however many
#: QGIS versions were bundled in, the thing that actually blew the old
#: fixed 20G default. Re-normalised over whichever dataset names are
#: actually requested (zfs-multi has no `overflow`), so these don't need
#: to sum to 1.0 on their own.
DATASET_WEIGHTS = {
    "nix": 0.45,
    "home": 0.30,
    "root": 0.15,
    "overflow": 0.10,
}

#: Minimum quota each dataset gets before the proportional split runs, so
#: a small disk doesn't starve `nix`/`root` down to uselessness.
DATASET_FLOORS_BYTES = {
    "nix": 12 * GIB,
    "home": 4 * GIB,
    "root": 4 * GIB,
    "overflow": 2 * GIB,
}


#: Parity disks per zfs-multi raid mode — see templates/disko/zfs-multi.nix.
RAID_PARITY_DISKS = {"stripe": 0, "raidz": 1, "raidz2": 2}


def multi_disk_usable_bytes(disk_bytes: list[int], *, esp_bytes: int, mode: str) -> int:
    """Rough usable-capacity estimate for a zfs-multi pool: the smallest
    disk (after its ESP partition) times the number of non-parity disks.
    ZFS's real usable space is a little under this once metadata/padding
    overhead is accounted for — deliberately conservative, and headroom
    absorbs the rest of the error rather than the quota math needing to
    be exact."""
    parity = RAID_PARITY_DISKS[mode]
    per_disk = min(d - esp_bytes for d in disk_bytes)
    data_disks = max(len(disk_bytes) - parity, 1)
    return int(per_disk * data_disks * 0.95)


def gib_str(n_bytes: int) -> str:
    """Whole GiB, floor-rounded, minimum 1G — disko's `quota` option wants
    a size string like "20G"."""
    return f"{max(n_bytes // GIB, 1)}G"


class DiskTooSmallError(ValueError):
    """Raised when a disk can't fit every dataset's floor plus the ESP
    reservation and headroom — better to fail in the wizard than mid-install."""


def quota_plan(
    disk_bytes: int,
    *,
    esp_bytes: int,
    reserved_bytes: int = 0,
    headroom_bytes: int = DEFAULT_HEADROOM_BYTES,
    datasets: tuple[str, ...] = ("root", "nix", "home", "overflow"),
) -> dict[str, str]:
    """Split what's left of `disk_bytes` — after the ESP partition, any
    other fixed real allocation (`reserved_bytes`, e.g. the atuin zvol),
    and a fixed headroom reserve — across `datasets` by weight. Returns
    disko-ready quota strings, e.g. {"nix": "54G", ...}.

    Every dataset gets its floor first; only the remainder above the
    combined floors is split by weight, so the returned quotas always sum
    to at most `disk_bytes - esp_bytes - reserved_bytes - headroom_bytes`
    — the headroom is never eaten into by rounding.
    """
    budget = disk_bytes - esp_bytes - reserved_bytes - headroom_bytes
    floor_total = sum(DATASET_FLOORS_BYTES[name] for name in datasets)
    if budget < floor_total:
        raise DiskTooSmallError(
            f"disk too small for this layout: {disk_bytes // GIB}G total leaves "
            f"{max(budget, 0) // GIB}G for datasets after the {esp_bytes // GIB}G ESP, "
            f"{reserved_bytes // GIB}G reserved, and {headroom_bytes // GIB}G headroom, "
            f"but {', '.join(datasets)} need {floor_total // GIB}G between them at minimum"
        )

    remainder = budget - floor_total
    weight_total = sum(DATASET_WEIGHTS[name] for name in datasets)
    plan = {}
    for name in datasets:
        extra = int(remainder * (DATASET_WEIGHTS[name] / weight_total))
        plan[name] = gib_str(DATASET_FLOORS_BYTES[name] + extra)
    return plan
