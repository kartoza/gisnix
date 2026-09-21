# Baboon — terminal typing-practice game. Defined in overlays/default.nix,
# previously never actually installed anywhere in this bundle (or in
# nix-config's own copy) despite the package existing — a dangling
# overlay entry, not a deliberate omission.
{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.baboon ];
}
