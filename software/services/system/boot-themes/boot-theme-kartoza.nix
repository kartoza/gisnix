# Kartoza-branded boot: Plymouth splash and matching GRUB menu.
#
# One member of the `bootTheme` choice group. The pair travels together —
# a Kartoza GRUB menu handing over to a QGIS splash would look like a fault —
# so the member is the pair, not either half.
#
# This replaces profiles/kartoza-boot.nix, which did exactly this and could
# only be selected by editing a host's desktop.nix.
{ ... }:
{
  imports = [
    ./kartoza-plymouth-theme.nix
    ./kartoza-grub-theme.nix
  ];
}
