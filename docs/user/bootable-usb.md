# Making a bootable USB stick

You need the `.iso` (from the [downloads
page](https://github.com/kartoza/gisnix/releases/latest) or [built
yourself](quickstart.md#1-get-the-iso)) and a USB drive of 4GB or more —
everything on it will be erased.

=== "Linux"

    **balenaEtcher** (GUI, works the same on every OS) — download from
    [balena.io/etcher](https://etcher.balena.io/), point it at the `.iso`
    and the drive, and click Flash.

    **`dd`**, if you'd rather not install anything:

    ```bash
    lsblk                          # find your USB drive's device name —
                                    # NOT a partition (sdb, not sdb1)
    sudo dd if=gisnix-installer.iso of=/dev/sdX bs=4M status=progress conv=fsync
    sync
    ```

    Triple-check `/dev/sdX` before running this — `dd` overwrites
    whatever device you point it at with no confirmation prompt. Writing
    to the wrong one destroys that disk's data.

    **GNOME Disks** — open it, select the USB drive, menu → "Restore Disk
    Image…", pick the `.iso`.

=== "macOS"

    **balenaEtcher** — same as above, download from
    [balena.io/etcher](https://etcher.balena.io/).

    **`dd`**, if you'd rather not install anything:

    ```bash
    diskutil list                  # find your USB drive, e.g. /dev/disk4
    diskutil unmountDisk /dev/disk4
    sudo dd if=gisnix-installer.iso of=/dev/rdisk4 bs=4m
    ```

    Use the `/dev/rdiskN` (raw) device, not `/dev/diskN` — it's
    dramatically faster, and still the same disk. As with Linux, confirm
    the device number before running this.

=== "Windows"

    **Rufus** — download from [rufus.ie](https://rufus.ie/), select the
    `.iso` and the USB drive, leave the partition scheme on its default
    (GPT for UEFI), and click Start.

    **balenaEtcher** works identically to the Linux/macOS instructions
    above if you'd rather use the same tool everywhere.

## Verifying the download (optional)

The release also publishes a `.sha256` checksum alongside the `.iso`.
Confirm the download wasn't corrupted before writing it to a drive:

```bash
sha256sum -c gisnix-installer.iso.sha256   # Linux
shasum -a 256 -c gisnix-installer.iso.sha256   # macOS
```

(On Windows, `CertUtil -hashfile gisnix-installer.iso SHA256` prints the
hash to compare by eye against the `.sha256` file's contents.)

## After it's written

Reboot the target machine with the USB drive plugged in, and pick it from
the boot menu (the key varies by manufacturer — F12, F10, Esc and Del are
common). Make sure Secure Boot is off and the firmware is set to UEFI, not
legacy/CSM — see the [quickstart](quickstart.md) for what happens next.
