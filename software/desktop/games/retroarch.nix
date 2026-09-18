{
  config,
  pkgs,
  ...
}:
{
  # Allow the specific unfree libretro cores
  # Unfree packages this file needs. Contributed to the shared
  # allow-list in software/services/system/unfree.nix — lists merge,
  # so this no longer competes with every other file that declares one.
  kartoza.unfreePackages = [
    "libretro-genesis-plus-gx"
    "libretro-snes9x"
    "libretro-fuse"
  ];

  environment.systemPackages = with pkgs; [
    (retroarch.overrideAttrs (old: {
      cores = with libretro; [
        genesis-plus-gx
        snes9x
        fuse
      ];
    }))
  ];
}
