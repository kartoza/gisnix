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
  # Koodo Reader pins electron 41, which is EOL and marked insecure —
  # same situation gui-apps.nix already carries for Logseq's electron 39.
  # Allow exactly that electron for exactly as long as we ship koodo-
  # reader; remove this line together with the package, or when nixpkgs
  # moves koodo-reader to a maintained electron.
  nixpkgs.config.permittedInsecurePackages = [ "electron-41.9.1" ];

  environment.systemPackages = [ pkgs.koodo-reader ];
}
