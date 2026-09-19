"""Everything the wizard has collected so far, threaded through the screens.
One mutable object rather than passing a dozen arguments — each screen reads
what it needs and fills in its own fields before advancing."""

from __future__ import annotations

from dataclasses import dataclass, field

#: The installer's default package selection: minimal base system plus a
#: minimal COSMIC desktop. Matches gen-host-config.py's ACTIVE list, so a
#: host created by the installer and one created by `gisnix create-host` start
#: from the same shape.
DEFAULT_BUNDLES = {
    "base",
    "desktop-environments-cosmic",
    "desktop-browsers",
    "services-system",
}

STORAGE_ZFS_ENCRYPTED_SINGLE = "zfs-encrypted-single"
STORAGE_XFS_SINGLE = "xfs-single"
STORAGE_ZFS_MULTI = "zfs-multi"


@dataclass
class InstallState:
    # welcome step
    console_font_size: int = 16  # pt; see installer/widgets.py's FontSizeSlider

    # host_mode step
    use_existing_host: bool = False
    existing_host_name: str | None = None

    # host_details step
    hostname: str = ""
    locale: str = "za-en"
    boot_theme: str = "kartoza"  # "kartoza" | "qgis"

    # user step
    username: str = ""
    full_name: str = ""
    password_hash: str = ""
    ssh_public_keys: list[str] = field(default_factory=list)

    # storage step
    storage_mode: str = STORAGE_ZFS_ENCRYPTED_SINGLE
    disks: list[str] = field(default_factory=list)  # one device, or several for zfs-multi
    zfs_raid_mode: str = "raidz"  # "stripe" | "raidz" | "raidz2", zfs-multi only
    zfs_multi_encrypted: bool = True  # zfs-multi only; single-disk ZFS is always encrypted
    zfs_passphrase: str = ""

    # bundles step
    bundles: set[str] = field(default_factory=lambda: set(DEFAULT_BUNDLES))

    # confirm step
    confirmed: bool = False

    def summary_lines(self) -> list[str]:
        lines = [
            f"Hostname:      {self.hostname}",
            f"User:          {self.username} ({self.full_name})" if self.full_name else f"User:          {self.username}",
            f"Locale:        {self.locale}",
            f"Boot theme:    {self.boot_theme}",
            f"Storage:       {_storage_label(self)}",
            f"Disk(s):       {', '.join(self.disks)}",
            f"Bundles:       {', '.join(sorted(self.bundles)) or '(none — base system only)'}",
        ]
        return lines


def _storage_label(state: InstallState) -> str:
    if state.storage_mode == STORAGE_ZFS_ENCRYPTED_SINGLE:
        return "ZFS, single disk, encrypted (AES-256-GCM passphrase)"
    if state.storage_mode == STORAGE_XFS_SINGLE:
        return "XFS, single disk, unencrypted"
    if state.storage_mode == STORAGE_ZFS_MULTI:
        enc = "encrypted" if state.zfs_multi_encrypted else "unencrypted"
        return f"ZFS, {len(state.disks)} disks, {state.zfs_raid_mode}, {enc}"
    return state.storage_mode
