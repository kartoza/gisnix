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

## 3. Run setup

You land in `~/gisnix` (the checkout baked onto the ISO), logged in as
`nixos` — not root. The banner tells you what to type; disk and network
changes need sudo:

```bash
sudo setup
```

and follow the wizard:

1. **Welcome** and a network check (offline installs can continue if the
   closure is already cached). The welcome screen also has a console font
   size control — focus it and press ←/→, and the whole display resizes
   immediately, before you commit to anything. The size you land on carries
   through to the installed machine's own console, too.
2. **New host, or an existing profile** — pick a profile if one is already
   committed somewhere gisnix can see it; otherwise start fresh.
3. **Hostname, locale, boot theme** (Kartoza or QGIS Plymouth/GRUB splash).
4. **User account** — username, password, and a way to get your SSH
   key(s) onto the machine: type a GitHub username and it pulls your
   public keys from `github.com/<username>.keys`, or paste key(s) in
   directly if you'd rather. Both are optional.
5. **Storage** — ZFS single-disk encrypted (recommended, AES-256-GCM
   passphrase), plain XFS single-disk, or multi-disk ZFS
   stripe/raidz/raidz2.
6. **Software** — installs the default bundles: a minimal base system
   plus a minimal COSMIC desktop. Add anything else afterwards with
   `gisnix configure`, the same picker used on any installed machine.
7. **Confirm** — type the hostname back to proceed. This is the point of
   no return: the selected disk(s) are erased.
8. **Install** — disko partitions and formats, `nixos-install` builds the
   system, and a tiny flake pinning gisnix is written to
   `~/nixos-config` on the new machine. This one build pulls COSMIC from
   stable nixpkgs rather than the bleeding-edge build every other gisnix
   host uses, so it's fully cached and doesn't compile a desktop from
   source — see [Afterwards](#afterwards) for the one command that moves
   you onto the latest COSMIC once you're booted.

Want to see the wizard first without touching a real disk? `setup
--mock` (or `gisnix setup --mock` from a gisnix checkout) fakes disks and
network and skips every destructive step — no sudo needed either, since
`--mock` touches nothing privileged.

## 4. First boot

Remove the USB drive, reboot, type the ZFS passphrase if you chose
encryption, and log in with the account you created.

## Afterwards {#afterwards}

`~/nixos-config` is the single source of truth from here. It's a plain
NixOS flake — the always-working path is:

```bash
cd ~/nixos-config
# edit hosts/<name>/config.nix: uncomment a bundle line to add it,
# comment one out to drop it (every bundle is listed, see
# references/bundles.md for what each one holds)
sudo nixos-rebuild switch --flake .#<name>
```

The desktop you just booted into is running stable COSMIC (see step 8
above), so it installed fast and didn't need to compile anything. Once
you're online, run this to move onto the same bleeding-edge COSMIC every
other gisnix host tracks:

```bash
gisnix update
```

This may compile something nixos-unstable's own cache hasn't built yet,
so expect it to take longer than a routine update — that cost only shows
up here, once, instead of during the install itself.

!!! note "The `gisnix configure` menu"
    On a full checkout that keeps `utils/` alongside `hosts/` — gisnix
    itself, or a downstream flake built the same way — `gisnix configure`
    gives you an interactive bundle picker instead of hand-editing. Running
    it usefully against a *standalone* tiny flake like the one the
    installer generates isn't wired up yet — see
    [Building on gisnix](../developer/downstream-flakes.md) for the
    current state of that gap.
