from __future__ import annotations

from textual.containers import VerticalGroup
from textual.widgets import Checkbox, Input, Label, RadioButton, RadioSet, Select, SelectionList

from .. import sizing
from ..repo import list_disks
from ..sizing import ATUIN_SIZE_BYTES, ESP_SIZE_BYTES
from ..state import STORAGE_XFS_SINGLE, STORAGE_ZFS_ENCRYPTED_SINGLE, STORAGE_ZFS_MULTI
from .base import WizardScreen

#: zfs-load-key(8): passphrase-format key material must be 8-512 bytes —
#: `zpool create` rejects anything outside that range. Checked here so a
#: bad passphrase fails at data-entry, not mid-install after disko has
#: already started partitioning the disk.
ZFS_PASSPHRASE_MIN = 8
ZFS_PASSPHRASE_MAX = 512

#: Select() options are (label, value) pairs.
RAID_MODES = [
    ("Stripe (no redundancy, min 2 disks)", "stripe"),
    ("RAIDZ (1-disk fault tolerance, min 3)", "raidz"),
    ("RAIDZ2 (2-disk fault tolerance, min 4)", "raidz2"),
]


class StorageScreen(WizardScreen):
    def __init__(self) -> None:
        super().__init__("Storage", next_label="Continue")
        self._disks = list_disks()

    def body(self):
        with VerticalGroup():
            yield Label("Storage mode")
            with RadioSet(id="storage-mode"):
                yield RadioButton(
                    "ZFS, single disk, encrypted (recommended)",
                    value=True,
                    id="mode-zfs-enc",
                )
                yield RadioButton("XFS, single disk, unencrypted", id="mode-xfs")
                yield RadioButton(
                    "ZFS, multiple disks, stripe/raidz/raidz2", id="mode-zfs-multi"
                )

            yield Label("Disk(s) — [b]everything on the selected disk(s) will be erased[/b]")
            disks = [(f"{d.device}  {d.size_human}  {d.model}".strip(), d.device) for d in self._disks]
            yield SelectionList[str](*disks, id="disk-list")

            yield Label("Multi-disk RAID mode (only used for the multi-disk option above)")
            yield Select(RAID_MODES, value="raidz", id="raid-mode-select")
            yield Checkbox("Encrypt multi-disk pool too", value=True, id="multi-encrypt")

            yield Label(
                "ZFS encryption passphrase (used for either ZFS option above, "
                "8-512 characters)"
            )
            yield Input(password=True, id="passphrase-input")
            yield Label("Confirm passphrase")
            yield Input(password=True, id="passphrase-confirm-input")

    def on_next(self) -> bool | None:
        mode_radio = self.query_one("#storage-mode", RadioSet).pressed_button
        mode_id = mode_radio.id if mode_radio else "mode-zfs-enc"
        mode = {
            "mode-zfs-enc": STORAGE_ZFS_ENCRYPTED_SINGLE,
            "mode-xfs": STORAGE_XFS_SINGLE,
            "mode-zfs-multi": STORAGE_ZFS_MULTI,
        }[mode_id]

        selected_disks = list(self.query_one("#disk-list", SelectionList).selected)
        needs_multi = mode == STORAGE_ZFS_MULTI
        min_disks = 1 if not needs_multi else {"stripe": 2, "raidz": 3, "raidz2": 4}[
            self.query_one("#raid-mode-select", Select).value
        ]
        if not needs_multi and len(selected_disks) != 1:
            self.set_error(
                "Select exactly one disk for a single-disk storage mode.", focus="#disk-list"
            )
            return False
        if needs_multi and len(selected_disks) < min_disks:
            self.set_error(
                f"That RAID mode needs at least {min_disks} disks selected.", focus="#disk-list"
            )
            return False

        encrypted = mode == STORAGE_ZFS_ENCRYPTED_SINGLE or (
            needs_multi and self.query_one("#multi-encrypt", Checkbox).value
        )
        if encrypted:
            passphrase = self.query_one("#passphrase-input", Input).value
            confirm = self.query_one("#passphrase-confirm-input", Input).value
            if not passphrase:
                self.set_error(
                    "A ZFS encryption passphrase is required for an encrypted pool.",
                    focus="#passphrase-input",
                )
                return False
            if len(passphrase) < ZFS_PASSPHRASE_MIN:
                self.set_error(
                    f"ZFS requires a passphrase of at least {ZFS_PASSPHRASE_MIN} "
                    "characters — shorter ones are rejected when the pool is created.",
                    focus="#passphrase-input",
                )
                return False
            if len(passphrase) > ZFS_PASSPHRASE_MAX:
                self.set_error(
                    f"ZFS accepts at most {ZFS_PASSPHRASE_MAX} characters for a passphrase.",
                    focus="#passphrase-input",
                )
                return False
            if passphrase != confirm:
                self.set_error("Passphrases do not match.", focus="#passphrase-confirm-input")
                return False
        else:
            passphrase = ""

        disk_sizes = {d.device: d.size_bytes for d in self._disks if d.device in selected_disks}
        if mode == STORAGE_ZFS_ENCRYPTED_SINGLE:
            try:
                sizing.quota_plan(
                    disk_sizes[selected_disks[0]],
                    esp_bytes=ESP_SIZE_BYTES,
                    reserved_bytes=ATUIN_SIZE_BYTES,
                )
            except sizing.DiskTooSmallError as exc:
                self.set_error(str(exc), focus="#disk-list")
                return False
        elif mode == STORAGE_ZFS_MULTI:
            usable = sizing.multi_disk_usable_bytes(
                list(disk_sizes.values()),
                esp_bytes=ESP_SIZE_BYTES,
                mode=self.query_one("#raid-mode-select", Select).value,
            )
            try:
                sizing.quota_plan(usable, esp_bytes=0, datasets=("root", "nix", "home"))
            except sizing.DiskTooSmallError as exc:
                self.set_error(str(exc), focus="#disk-list")
                return False

        state = self.app.state
        state.storage_mode = mode
        state.disks = selected_disks
        state.disk_sizes = disk_sizes
        state.zfs_raid_mode = self.query_one("#raid-mode-select", Select).value
        state.zfs_multi_encrypted = encrypted if needs_multi else state.zfs_multi_encrypted
        state.zfs_passphrase = passphrase
        return True
