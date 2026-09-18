# Thorium Reader — EPUB, PDF and audiobook reader from EDRLab, with strong
# accessibility support.
#
# This was a hand-rolled AppImage fetch pinned to v3.0.0 with
# `sha256 = "<insert-correct-sha256>"` — a literal placeholder. It had never
# been able to build, which is consistent with nothing ever importing it.
#
# nixpkgs packages it, currently 3.4.0.
{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.thorium-reader ];
}
