{
  lib,
  hostname,
  ...
}:
{
  nixpkgs.config.allowUnfree = false;

  imports = [
    # Disk layout (disko) — owns the partition table, the encrypted NIXROOT
    # pool and every mountpoint. hardware.nix deliberately declares no
    # fileSystems.
    ./disks.nix
    ./hardware.nix

    ../../software/locale/locale-za-en.nix

    # The installer writes one of these per machine — see users/example.nix
    # for the template it starts from.
    ../../users/example.nix

    # Always-on core, independent of the optional software/ bundles in
    # config.nix: Nix settings/hardening, the desktop, Kartoza branding
    # (colors/wallpaper — both a Kartoza and a QGIS variant ship, pick with
    # bootTheme in config.nix), Stylix theming, and locale/timezone plumbing.
    ../../profiles/common.nix
    ../../profiles/cosmic-desktop.nix
    ../../profiles/kartoza.nix
    ../../profiles/stylix.nix
    ../../profiles/services.nix
  ];

  networking.hostName = hostname;
}
