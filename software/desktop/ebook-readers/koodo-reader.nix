# Koodo Reader — cross-platform e-book reader with library management.
#
# This was a hand-rolled AppImage wrapper: a package derivation taking
# { appimageTools, fetchurl } that had been filed as a NixOS module. The
# module system passes `outputs`, which its argument list rejected, so it
# could never be imported — which is why nothing imported it, and why the
# breakage went unnoticed until the bundle work adopted it.
#
# nixpkgs packages it, so none of that is needed.
{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.koodo-reader ];
}
