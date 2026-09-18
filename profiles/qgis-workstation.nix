# QGIS Workstation Profile
#
# The shared shape of the QGIS field workstations (island, mainland): the
# QGIS-branded boot experience, encrypted ZFS, the two QGIS channels that are
# actually run, Google Earth Pro and Steam.
#
# These hosts differ only by locale, so that stays in each host's desktop.nix
# and everything else lives here. Import this and set the locale; do not
# re-import the members individually.
{ ... }:
{
  imports = [
    # QGIS "Spatial without Compromise" Plymouth + GRUB pair.

    ../software/base/zfs.nix

    # QGIS channels. Pinned historical series (2.18 and friends) and the dev
    # channel are opt-in bundles in `kz configure` under desktop-gis; only
    # the two rolling channels are defaults.
    ../software/desktop/gis/qgis-latest.nix
    ../software/desktop/gis/qgis-ltr.nix
    # ../software/desktop/gis/qgis-dev.nix

    ../software/desktop/gis/google-earth-pro.nix
    ../software/desktop/games/steam.nix
  ];
}
