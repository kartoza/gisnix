{
  config,
  lib,
  pkgs,
  kartoza-grub-themes, # set in overlays/default.nix
  ...
}:
{
  # QGIS "Spatial without Compromise" GRUB theme.
  #
  # Reproduces the QGIS keynote title slide, colour-matched to the QGIS
  # Plymouth splash for a continuous GRUB → Plymouth hand-off. It replaced an
  # older BigSUR-derived topographic theme, which was removed once nothing
  # imported it.
  boot.loader.grub.theme =
    kartoza-grub-themes.packages.${pkgs.stdenv.hostPlatform.system}.qgis-spatial;

  # Intermediate splash shown between the GRUB menu selection and
  # Plymouth taking over — reuses the same "Spatial without Compromise"
  # composition so the transition is seamless.
  # See https://discourse.nixos.org/t/how-to-use-boot-loader-grub-splashimage/23748
  boot.loader.grub.splashImage = ../../../../resources/qgis-spatial-splash.png;

  # Try common native resolutions before GRUB's `auto` fallback so the
  # theme renders full-screen instead of in a small floating panel on
  # high-DPI displays.
  #
  # mkDefault so the boot-vm profile (profiles/boot-vm.nix, which pins
  # virtualisation.resolution → gfxmodeBios) can override these inside
  # QEMU without a conflict — that keeps GRUB and the Plymouth
  # framebuffer at the same resolution during the bootvm test.  On real
  # hardware nothing else sets these, so the full-res cascade applies.
  boot.loader.grub.gfxmodeEfi = lib.mkDefault "3840x2160,2560x1600,2560x1440,1920x1200,1920x1080,1600x900,1366x768,auto";
  boot.loader.grub.gfxmodeBios = lib.mkDefault "1920x1080,1600x900,1366x768,1280x1024,1024x768,auto";
}
