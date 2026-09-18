{
  config,
  lib,
  pkgs,
  kartoza-grub-themes, # set in overlays/default.nix
  ...
}:
{

  boot.loader.grub.theme = kartoza-grub-themes.packages.${pkgs.stdenv.hostPlatform.system}.kartoza;
  # This is for the intermediate screen
  # between choosing a boot option and when
  # plymouth starts
  # See https://discourse.nixos.org/t/how-to-use-boot-loader-grub-splashimage/23748
  boot.loader.grub.splashImage = ../../../../resources/kartoza-wallpaper.png;

  # Try a cascade of common laptop / monitor native resolutions before
  # falling back to GRUB's `auto`.  Without this GRUB picks whatever the
  # EFI GOP reports first — often a 1024x768 fallback — which renders
  # the theme in a small floating panel on high-DPI displays (visible
  # in the boot-hardware IMG_7796 photo).  GRUB tries each mode in
  # order until one succeeds against the current firmware GOP.
  # mkDefault so nixpkgs' qemu-vm.nix — which pins gfxmodeBios to the
  # emulated display's 1024x768 — can win inside a VM without a conflict.
  # Without it, `kz vm <host>` on any host importing this theme failed to
  # evaluate at all: two normal-priority definitions of the same option.
  # On real hardware nothing else sets these, so the full-res cascade
  # applies. qgis-spatial-grub-theme.nix has carried this since the boot-vm
  # work; its twin never got the same treatment.
  boot.loader.grub.gfxmodeEfi = lib.mkDefault "3840x2160,2560x1600,2560x1440,1920x1200,1920x1080,1600x900,1366x768,auto";
  boot.loader.grub.gfxmodeBios = lib.mkDefault "1920x1080,1600x900,1366x768,1280x1024,1024x768,auto";
}
