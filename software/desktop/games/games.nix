{ pkgs, ... }:
{
  # Assorted open-source games. Kept small and installed system-wide rather
  # than per-user, so a guest session has something to play.
  #
  # `luanti` was `minetest` until upstream renamed it. That rename had already
  # happened when this module was adopted into the desktop-games bundle, and
  # nixpkgs threw on evaluation — the module had gone unimported for long
  # enough that nobody had noticed.
  environment.systemPackages = with pkgs; [
    warzone2100 # real-time strategy
    luanti # voxel sandbox, formerly Minetest
    atanks # artillery game
  ];
}
