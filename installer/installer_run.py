"""Runs the actual install: disko partitions/formats/mounts the disk(s),
nixos-install builds and installs the system, and the tiny per-machine flake
is copied into the new user's home so `gisnix configure`/`gisnix update` work there
exactly as they do on any other gisnix machine.

Each step is a generator yielding progress lines, so the Textual screen
driving this can stream them into a log widget rather than blocking with no
feedback — the single biggest thing tuinix got right that a naive
subprocess.run() would not.
"""

from __future__ import annotations

import shutil
import subprocess
import tempfile
import time
from collections.abc import Iterator
from pathlib import Path

from .repo import GISNIX_ROOT, MOCK
from .state import InstallState
from .writer import write_existing_host, write_new_host

MOUNT_ROOT = Path("/mnt")


def _stream(cmd: list[str], **kwargs) -> Iterator[str]:
    yield f"$ {' '.join(cmd)}"
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1, **kwargs
    )
    assert proc.stdout is not None
    for line in proc.stdout:
        yield line.rstrip("\n")
    code = proc.wait()
    if code != 0:
        raise RuntimeError(f"command failed ({code}): {' '.join(cmd)}")


def run_install_mock(state: InstallState) -> Iterator[str]:
    """--mock: write the real host/user/flake files to a temp dir (so
    there's something real to eyeball), then fake every step that would
    touch a disk, run nix, or need root. No subprocess, no network, no
    /mnt — safe to run from any ordinary terminal, repeatedly, in seconds.
    """
    if GISNIX_ROOT is None:
        raise RuntimeError("gisnix checkout not found on this system")

    work_dir = Path(tempfile.mkdtemp(prefix="gisnix-install-mock-"))
    yield f"[MOCK] Working in {work_dir}"

    if state.use_existing_host:
        write_existing_host(state, work_dir)
    else:
        write_new_host(state, work_dir)
    yield "[MOCK] Host and user files written for real — inspect them at the path above."
    for f in sorted(work_dir.rglob("*.nix")):
        yield f"  {f.relative_to(work_dir)}"

    fake_steps = [
        "── [MOCK] Pointing the new flake at this ISO's own gisnix copy ──",
        "── [MOCK] Partitioning and formatting (disko) ── (skipped, no disk touched)",
        "── [MOCK] Installing NixOS (nixos-install) ── (skipped, no root/build)",
        "── [MOCK] Re-pointing the installed flake at the public gisnix repo ──",
        "── [MOCK] Copying the flake into the new machine ── (skipped)",
        "── Done ──",
        f"Reboot, remove the USB drive, and log in as {state.username}.",
        "~/nixos-config is the single source of truth from here — gisnix configure, gisnix update.",
    ]
    for line in fake_steps:
        time.sleep(0.3)
        yield line


def run_install(state: InstallState) -> Iterator[str]:
    if MOCK:
        yield from run_install_mock(state)
        return

    if GISNIX_ROOT is None:
        raise RuntimeError("gisnix checkout not found on this system")

    work_dir = Path(tempfile.mkdtemp(prefix="gisnix-install-"))
    yield f"Working in {work_dir}"

    if state.use_existing_host:
        write_existing_host(state, work_dir)
    else:
        write_new_host(state, work_dir)
    yield "Host and user files written."

    yield "── Pointing the new flake at this ISO's own gisnix copy ──"
    # GISNIX_ROOT is already on disk (it's what the installer itself runs
    # from) — override the `gisnix` input to it rather than re-fetching from
    # GitHub. Faster, works offline, and installs the exact revision the ISO
    # was built from rather than whatever HEAD happens to be at install time.
    # Done before disko too: disko partitions via `--flake`, which needs the
    # input resolved just as much as nixos-install does.
    yield from _stream(
        [
            "nix",
            "--extra-experimental-features",
            "nix-command flakes",
            "flake",
            "lock",
            "--override-input",
            "gisnix",
            f"path:{GISNIX_ROOT}",
            str(work_dir),
        ]
    )

    yield "── Partitioning and formatting (disko) ──"
    yield "THIS ERASES THE TARGET DISK(S). No further confirmation follows."
    # --flake, not a raw disks.nix path: disks.nix takes `gisnixRoot` as a
    # module argument (see writer.render_disks_nix), which only exists once
    # evaluated as part of the full host through mkHost's specialArgs —
    # evaluating the file standalone would fail with a missing argument.
    # Uses the `disko` CLI already on PATH (from installerPackage's
    # runtimeInputs) rather than re-fetching over the network.
    #
    # --yes-wipe-all-disks: disko has its OWN "are you sure you want to wipe
    # <device>?" y/n prompt before it touches anything, on top of the
    # wizard's own confirm screen. That prompt reads from stdin, which is
    # never wired up for interactive input here — Textual owns the
    # keyboard for its own event loop, so disko's `input()` call never
    # sees a keystroke and the process just aborts instantly. The wizard's
    # confirm screen (type the hostname back) is the actual "I understand,
    # destroy this disk" gate; by the time this runs that has already
    # happened, so disko's own copy of the same question is redundant, not
    # a safety net being skipped.
    disko_cmd = [
        "disko",
        "--mode",
        "destroy,format,mount",
        "--yes-wipe-all-disks",
        "--flake",
        f"{work_dir}#{state.hostname}",
    ]
    # ZFS encryption prompts for a passphrase on the pool's own stdin; disko
    # inherits the wizard's TTY for that one interactive moment. If the mode
    # is ZFS-encrypted, the passphrase is piped in non-interactively instead
    # — twice, since disko/zfs asks for confirmation on creation.
    if state.zfs_passphrase:
        proc_input = f"{state.zfs_passphrase}\n{state.zfs_passphrase}\n"
        yield "$ " + " ".join(disko_cmd)
        proc = subprocess.Popen(
            disko_cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        assert proc.stdin is not None and proc.stdout is not None
        proc.stdin.write(proc_input)
        proc.stdin.close()
        for line in proc.stdout:
            yield line.rstrip("\n")
        code = proc.wait()
        if code != 0:
            raise RuntimeError(f"disko failed ({code})")
    else:
        yield from _stream(disko_cmd)

    yield "── Installing NixOS (nixos-install) ──"
    yield from _stream(
        [
            "nixos-install",
            "--root",
            str(MOUNT_ROOT),
            "--flake",
            f"{work_dir}#{state.hostname}",
            "--no-root-passwd",
        ]
    )

    yield "── Re-pointing the installed flake at the public gisnix repo ──"
    # The lock above was pinned to THIS ISO's local copy so the install
    # itself needed no network. That local store path won't be a meaningful
    # reference once the machine is running its own life — swap it back to
    # the real github: URL before it's copied into the new home, so `gisnix
    # update`/`nix flake update` behave normally from first boot on. Best
    # effort: this needs network, and the system is already fully installed
    # and bootable at this point either way — a failure here just means the
    # new owner runs `nix flake update` once they're online, not a failed
    # install.
    try:
        yield from _stream(
            [
                "nix",
                "--extra-experimental-features",
                "nix-command flakes",
                "flake",
                "lock",
                "--override-input",
                "gisnix",
                "github:kartoza/gisnix",
                str(work_dir),
            ]
        )
    except RuntimeError as exc:
        yield f"(skipped — {exc}; run `nix flake update` once online)"

    yield "── Copying the flake into the new machine ──"
    dest = MOUNT_ROOT / "home" / state.username / "nixos-config"
    shutil.copytree(work_dir, dest, dirs_exist_ok=True)
    yield from _stream(
        [
            "nixos-enter",
            "--root",
            str(MOUNT_ROOT),
            "--command",
            f"chown -R {state.username}:users /home/{state.username}/nixos-config",
        ]
    )

    yield "── Done ──"
    yield f"Reboot, remove the USB drive, and log in as {state.username}."
    yield "~/nixos-config is the single source of truth from here — gisnix configure, gisnix update."
