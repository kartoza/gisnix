# Profile applied only when running `nix run .#<host>-bootvm`.
#
# The default `<host>-vm` app boots QEMU with `-kernel` and `-initrd`
# passed directly, so GRUB never runs and Plymouth has no chance to
# render (and profiles/development.nix forces graphics off anyway).
# That makes the standard VM useless for iterating on the boot
# experience.
#
# This profile rewires the test VM to:
#   * boot through the host's configured bootloader (so the Kartoza
#     GRUB theme + splash actually load),
#   * use OVMF / UEFI (every host uses efiSupport + efiInstallAsRemovable),
#   * render to a graphical QEMU window so Plymouth is visible.
#
# Trade-offs:
#   * First boot per host is slow (~30-60 s) because it provisions an
#     ESP and runs grub-install into a fresh qcow.
#   * The qcow persists at /tmp/<host>.qcow2 across runs, so subsequent
#     iterations are fast.  Delete it to force re-provisioning if you
#     change anything in the bootloader install path itself.
{ lib, ... }:
{
  virtualisation.vmVariant = {
    virtualisation.useBootLoader = true;

    # IMPORTANT: useEFIBoot pulls in OVMF, which combined with
    # `useBootLoader = true` reliably OOM-kills the inner disk-image
    # builder VM (its memSize is hard-coded to 1024 MB in nixpkgs'
    # make-disk-image.nix and is not exposed as a NixOS option). For
    # *theme* iteration the BIOS path is functionally identical: GRUB
    # renders the same theme regardless of firmware.
    #
    # Hosts that need EFI in the bootvm must override this with
    # `lib.mkForce true` in their own vmVariant AND ensure their
    # build host has enough headroom for the OVMF+grub-efi builder.
    virtualisation.useEFIBoot = false;

    # Override profiles/development.nix which forces `graphics = false`
    # so headless devs can run `<host>-vm` for config checks.
    virtualisation.graphics = lib.mkForce true;

    virtualisation.memorySize = lib.mkDefault 4096;
    virtualisation.diskSize = lib.mkDefault 4096;

    # Pin GRUB's gfxmode and the guest QEMU display to the same explicit
    # resolution.  Without this, GRUB defaults to 1024x768 and the KMS
    # drivers (bochs / qxl / virtio_gpu) bring the framebuffer up at a
    # slightly different mode when the kernel takes over — the splash
    # rendered by GRUB is ~16 lines shorter than the splash rendered by
    # Plymouth, producing a visible vertical offset at the handoff.
    # This value also becomes `boot.loader.grub.gfxmodeBios` via
    # qemu-vm.nix:1274.
    virtualisation.resolution = {
      x = 1024;
      y = 768;
    };

    # Force the kernel's video mode to match GRUB's exactly so the KMS
    # takeover produces the same framebuffer geometry as GRUB was using.
    # Paired with boot.loader.grub.gfxpayloadBios = "keep" in the host,
    # this eliminates the mode transition altogether.
    boot.kernelParams = [ "video=1024x768" ];

    # Put the writable qcow under /tmp (obviously disposable) instead
    # of $PWD where it lingers across reboots and silently re-runs
    # stale configs.
    #
    # NOTE: the qemu-vm wrapper only creates this file if missing, so
    # config changes don't automatically get a fresh image.  The
    # `<host>-bootvm` flake app deletes this path before launching to
    # guarantee freshness.  Delete it manually if you bypass the
    # wrapper (e.g. by invoking `nixos-vm` directly).
    virtualisation.diskImage = "/tmp/nixos-bootvm.qcow2";
  };

  # Override the inner disk-image builder VM's memSize.  nixpkgs hard-codes
  # `memSize ? 1024` in `lib/make-disk-image.nix` (called from
  # qemu-vm.nix's `systemImage`) and does not expose it as a NixOS option,
  # so the only knob we have is at the `vmTools.runInLinuxVM` layer.  4
  # GiB is enough for grub-install + plymouth + a small closure copy
  # without OOM.
  nixpkgs.overlays = [
    (final: prev: {
      vmTools = prev.vmTools // {
        runInLinuxVM =
          drv:
          prev.vmTools.runInLinuxVM (
            drv.overrideAttrs (old: {
              memSize = 4096;
            })
          );
      };
    })
  ];
}
