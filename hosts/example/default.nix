{
  lib,
  hostname,
  gisnixRoot,
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

    # The installer writes one of these per machine — see users/example.nix
    # for the template it starts from. Same-shape repo either way (host and
    # user directories at the same relative position), so this stays a
    # plain relative import even in a downstream flake.
    ../../users/example.nix

    # Shared modules that live in gisnix itself, not in this host's own
    # repo — reached via gisnixRoot rather than a `../../` path, so this
    # host directory also works unmodified inside a downstream flake that
    # pins gisnix as an input and points hostPath at a copy of this
    # directory in ITS OWN tree (see flake.nix's mkHost).
    (gisnixRoot + "/software/locale/locale-za-en.nix")

    # Always-on core, independent of the optional software/ bundles in
    # config.nix: Nix settings/hardening, the desktop, Kartoza branding
    # (colors/wallpaper — both a Kartoza and a QGIS variant ship, pick with
    # bootTheme in config.nix), Stylix theming, and locale/timezone plumbing.
    (gisnixRoot + "/profiles/common.nix")
    (gisnixRoot + "/profiles/cosmic-desktop.nix")
    (gisnixRoot + "/profiles/kartoza.nix")
    (gisnixRoot + "/profiles/stylix.nix")
    (gisnixRoot + "/profiles/services.nix")
  ];

  networking.hostName = hostname;
}
