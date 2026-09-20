# ZFS root: pool behaviour, the bootloader that has to understand it, and the
# passphrase prompt at boot.
#
# This was two files pretending to be alternatives, and neither name was true.
# `zfs-no-encryption.nix` held the common setup AND set
# `boot.zfs.requestEncryptionCredentials = true` — the file named "no
# encryption" asked for the encryption passphrase. `zfs-encryption.nix`
# imported it and set the very same option a second time. Six hosts imported
# the second one, so every one of them was getting the first as well.
#
# There is only ever one behaviour here, so there is now one file — and that
# matches the policy: ZFS on this fleet is always encrypted. These are
# laptops that leave the building and servers holding client data, so there
# is no case for an unencrypted pool and no switch offered for one.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.kartoza.zfs;
in
{
  options.kartoza.zfs.arcMaxGiB = lib.mkOption {
    type = lib.types.ints.positive;
    default = 2;
    example = 6;
    description = ''
      Ceiling on the ZFS ARC, in GiB.

      OpenZFS on Linux defaults `zfs_arc_max` to all-but-1GiB, so a 92 GiB
      machine entitles the ARC to 91 GiB. ARC is reclaimable, but reclaim is
      not instantaneous, and a large allocation arriving while the ARC is fat
      is a well-known route to an OOM kill — especially here, where every host
      has `swapDevices = [ ]` and therefore no cushion at all.

      Set this per host, in that host's hardware.nix, next to the rest of what
      is known about its physical memory. The default of 2 GiB is deliberately
      conservative: it is safe on a small VM and merely unambitious on a large
      workstation, which is the right way round for a value nobody has tuned.
    '';
  };

  config = {
    # See https://github.com/mcdonc/p51-thinkpad-nixos/tree/zfsvid
    # for notes on how this was originally set up.
    services.zfs.autoScrub.enable = true;

    boot.supportedFilesystems = [ "zfs" ];

    # Force-importing a pool skips ZFS's own check that the pool isn't
    # already imported (and potentially still live) elsewhere. This used to
    # be false here on the theory that disko creates the pool fresh in the
    # same boot that mounts it, so the hostid always matches — that theory
    # is wrong, confirmed against a real install ("cannot import 'NIXROOT':
    # pool was previously in use from another system... Last accessed by
    # nixos (hostid=...)"). Disko creates the pool while still running
    # under the LIVE ISO's own ambient hostid; the INSTALLED system boots
    # with a different one — installer/writer.py generates a fresh,
    # per-host networking.hostId for the target config, unrelated to
    # whatever the installer environment happened to be using. Every
    # install's first boot hits this mismatch, unavoidably. `true` only
    # matters for that one boot: importing successfully re-stamps the pool
    # with the booting system's own hostid, so every boot after the first
    # already matches and force is a no-op — this is what tuinix already
    # does, unconditionally, with no reported issue.
    boot.zfs.forceImportRoot = true;

    # Prompt for the passphrase during boot. Pools are always encrypted here,
    # so this is unconditional — without it an encrypted root fails to mount and
    # the machine drops to an emergency shell.
    boot.zfs.requestEncryptionCredentials = true;

    # GRUB, in the removable-media EFI layout. Hosts that need something else —
    # systemd-boot, a fixed EFI entry — override this in their hardware.nix.
    boot.loader.grub.enable = true;
    boot.loader.grub.devices = [ "nodev" ];
    boot.loader.grub.efiInstallAsRemovable = true;
    boot.loader.grub.efiSupport = true;

    # os-prober scans every attached block/optical device for other
    # operating systems to add to the boot menu — pointless here, since
    # every gisnix install path (like forceImportRoot above) creates the
    # target disk fresh via disko, single-OS, in the same boot that
    # installs it. Worse than pointless during the install itself: the
    # live ISO is still attached as its own virtual CD-ROM at that point,
    # and os-prober scanning a slow/emulated optical device is a
    # well-known way for `install-grub.sh` to crawl or hang outright.
    boot.loader.grub.useOSProber = false;

    # networking.hostId is required by ZFS and is set per host in hardware.nix.

    # Cap the ARC. A modprobe option rather than a boot-time script:
    #
    # This used to be computed at boot by a systemd unit reading MemTotal, on
    # the reasoning that Nix cannot know the target host's RAM. True, but the
    # host's own hardware.nix does — it is the file that describes that machine's
    # hardware — so the value belongs there and the whole apparatus of a unit, a
    # dotfile and a shell script disappears.
    #
    # It also removes a real fragility: that script was read by relative path,
    # and moving its module one directory shallower silently produced an absolute
    # /nix/store path that evaluated cleanly and failed the build.
    boot.extraModprobeConfig = ''
      options zfs zfs_arc_max=${toString (cfg.arcMaxGiB * 1024 * 1024 * 1024)}
    '';
  };
}
