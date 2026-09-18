# QGIS "Spatial without Compromise" boot: Plymouth splash and matching GRUB
# menu.
#
# One member of the `bootTheme` choice group. The GRUB menu and the Plymouth
# splash share the same navy cartographic artwork, strapline and QGIS-green
# accent, and the GRUB menu sits where the Plymouth "Q" logo appears, so the
# hand-off is continuous — which is why the member is the pair rather than
# either half.
#
# This replaces profiles/qgis-boot.nix, which did exactly this and could only
# be selected by editing a host's desktop.nix.
{ ... }:
{
  imports = [
    ./qgis-plymouth-theme.nix
    ./qgis-spatial-grub-theme.nix
  ];
}
