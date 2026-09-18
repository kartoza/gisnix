{ pkgs, ... }:
{
  # QGIS "Spatial without Compromise" boot splash.
  #
  # Structurally identical to software/services/system/kartoza-plymouth-theme.nix
  # (same quiet-boot kernel params so Plymouth owns the screen from
  # initrd through the display-manager hand-off); only the theme package
  # and name differ.  The package is provided by the kartoza-plymouth-theme
  # flake and surfaced as pkgs.qgis-plymouth-theme via overlays/default.nix.
  boot.initrd.systemd.enable = true;

  # 3 suppresses KERN_ERR runtime noise during the Plymouth→DM handoff.
  boot.consoleLogLevel = 3;

  boot.kernelParams = [
    "quiet"
    "rd.udev.log_level=3"
    "systemd.show_status=false"
    "udev.log_level=3"
  ];

  boot.plymouth = {
    enable = true;
    themePackages = [ pkgs.qgis-plymouth-theme ];
    theme = "qgis";
  };
}
