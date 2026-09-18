# GRASS GIS.
#
# Its own module for the same reason saga.nix is: every QGIS channel used to
# list `pkgs.grass` alongside itself, so a host taking the packaged channels
# declared it three times over, and the source-build channels three more. One
# declaration, imported once by the bundle.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    grass
  ];
}
