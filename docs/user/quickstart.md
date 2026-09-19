# Quickstart

## 1. Get the ISO

Build it yourself (there's no release build yet):

```bash
git clone https://github.com/kartoza/gisnix
cd gisnix
nix build .#nixosConfigurations.installer.config.system.build.isoImage
```

The `.iso` lands in `result/iso/`.

## 2. Boot it

Flash the ISO to a USB drive and boot the target machine from it — UEFI
required, Secure Boot off. Or try it first in a VM: `nix run .#test-install`
builds the ISO and boots it in QEMU with a persistent test disk. A plain
UEFI ISO also boots fine in VirtualBox or VMware without any hypervisor-
specific variant.

## 3. Run the installer

You land in a root shell in `~/gisnix` (the checkout baked onto the ISO).
Run:

```bash
installer
```

and follow the wizard:

1. **Welcome** and a network check (offline installs can continue if the
   closure is already cached).
2. **New host, or an existing profile** — pick a profile if one is already
   committed somewhere gisnix can see it; otherwise start fresh.
3. **Hostname, locale, boot theme** (Kartoza or QGIS Plymouth/GRUB splash).
4. **User account** — username, password, optional SSH public key(s).
5. **Storage** — ZFS single-disk encrypted (recommended, AES-256-GCM
   passphrase), plain XFS single-disk, or multi-disk ZFS
   stripe/raidz/raidz2.
6. **Software** — the same bundle picker `gisnix configure` uses on an
   installed machine. Defaults to a minimal base system plus a minimal
   COSMIC desktop; add more now or later.
7. **Confirm** — type the hostname back to proceed. This is the point of
   no return: the selected disk(s) are erased.
8. **Install** — disko partitions and formats, `nixos-install` builds the
   system, and a tiny flake pinning gisnix is written to
   `~/nixos-config` on the new machine.

Want to see the wizard first without touching a real disk? `installer
--mock` (or `gisnix installer --mock` from a gisnix checkout) fakes disks and
network and skips every destructive step.

## 4. First boot

Remove the USB drive, reboot, type the ZFS passphrase if you chose
encryption, and log in with the account you created.

## Afterwards

`~/nixos-config` is the single source of truth from here. It's a plain
NixOS flake — the always-working path is:

```bash
cd ~/nixos-config
# edit hosts/<name>/config.nix: uncomment a bundle line to add it,
# comment one out to drop it (every bundle is listed, see
# references/bundles.md for what each one holds)
sudo nixos-rebuild switch --flake .#<name>
```

!!! note "The `gisnix configure` menu"
    On a full checkout that keeps `utils/` alongside `hosts/` — gisnix
    itself, or a downstream flake built the same way — `gisnix configure`
    gives you an interactive bundle picker instead of hand-editing. Running
    it usefully against a *standalone* tiny flake like the one the
    installer generates isn't wired up yet — see
    [Building on gisnix](../developer/downstream-flakes.md) for the
    current state of that gap.
