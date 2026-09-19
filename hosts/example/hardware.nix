{
  modulesPath,
  config,
  lib,
  pkgs,
  ...
}:
{
  # example — a QEMU/libvirt VM, the installer's own test target. This is a
  # disko install: the partition table, the (by default encrypted) NIXROOT
  # pool and every mountpoint are declared in ./disks.nix. Do NOT add
  # `fileSystems.*` entries here — disko generates them.
  #
  # For real hardware, replace this file with the one `gisnix create-host`
  # generates from the running system (or with the module list `nixos-
  # generate-config` produces on the target machine).
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # disko owns the ESP; GRUB installs to it as a removable EFI binary.
  boot.loader.grub = {
    devices = [ "nodev" ];
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  boot.initrd.availableKernelModules = [
    "ahci"
    "xhci_pci"
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "sd_mod"
    "sr_mod"
    "nvme"
    "ehci_pci"
    "usbhid"
    "usb_storage"
    "sdhci_pci"
  ];
  # virtio_gpu early so KMS is up before Plymouth draws.
  boot.initrd.kernelModules = [ "virtio_gpu" ];
  # Guest, so the host's vendor is whatever it is — both are harmless, only
  # the matching one loads. Also covers VMware/VirtualBox nested-KVM hosts.
  boot.kernelModules = [
    "kvm-intel"
    "kvm-amd"
  ];
  boot.extraModulePackages = [ ];
  swapDevices = [ ];

  # ZFS support (used when disks.nix picks the ZFS-encrypted template).
  # forceImportRoot is set centrally in software/base/zfs.nix, not here.
  boot.supportedFilesystems = [ "zfs" ];
  # NIXROOT is encrypted by default (see disks.nix) — prompt for the
  # passphrase at boot. Harmless if the plain XFS template was chosen
  # instead: there is no ZFS pool to prompt for.
  boot.zfs.requestEncryptionCredentials = true;
  # Systemd-based initrd is needed for reliable ZFS passphrase prompting.
  boot.initrd.systemd.enable = true;
  services.zfs.autoScrub.enable = true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";

  # COSMIC is a Wayland compositor and needs a working KMS device — give the
  # guest a virgl-capable display (3D acceleration on) or cosmic-comp falls
  # back to llvmpipe and the session is painfully slow.
  hardware.graphics.enable = true;

  # QEMU/libvirt guest integration: clean shutdown/freeze control, clipboard
  # sharing and display auto-resize. Harmless no-ops under VirtualBox/VMware.
  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;
}
