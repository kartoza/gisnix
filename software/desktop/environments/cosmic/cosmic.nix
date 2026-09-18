# COSMIC Desktop Environment — the kartoza.cosmic option and the settings
# that depend on it.
#
# This was default.nix and imported its siblings itself. It no longer does:
# the bundle lists packages.nix and ssh-gpg.nix alongside this file, so there
# is one place saying what the group contains. A default.nix that quietly
# imported things was invisible to the bundle system — which is how the option
# defined here went missing when the profile stopped importing the directory.
#
# COSMIC Desktop Environment Module
# Modular configuration for Kartoza COSMIC setup
#
# This module provides:
# - COSMIC desktop with Wayland (System76's Rust-based desktop)
# - Kartoza branding and theming
# - cosmic-greeter display manager
{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:

with lib;

let
  cfg = config.kartoza.cosmic;
  # COSMIC packages come from nixpkgs-unstable via overlay
  cosmicPkgs = pkgs;
in
{
  options.kartoza.cosmic = {
    enable = mkEnableOption "Kartoza COSMIC desktop environment";

    wallpaper = mkOption {
      type = types.path;
      default = ../../../../resources/kartoza-wallpaper.png;
      description = "Path to wallpaper image for COSMIC desktop and greeter";
    };
  };

  config = mkIf cfg.enable {
    # Enable COSMIC desktop environment (NixOS 25.05+)
    services.desktopManager.cosmic.enable = true;

    # Enable System76 scheduler for performance improvements
    services.system76-scheduler.enable = true;

    # Enable COSMIC greeter (login screen)
    services.displayManager.cosmic-greeter.enable = true;

    # Portal services are enabled by services.desktopManager.cosmic
    # No need to add xdg-desktop-portal-cosmic manually
    xdg.portal.enable = true;

    # Set default applications via xdg-mime
    xdg.mime = {
      enable = true;
      defaultApplications = {
        "application/pdf" = [ "org.gnome.Evince.desktop" ];
        "text/html" = [ "firefox.desktop" ];
        "x-scheme-handler/http" = [ "firefox.desktop" ];
        "x-scheme-handler/https" = [ "firefox.desktop" ];
        "x-scheme-handler/about" = [ "firefox.desktop" ];
        "x-scheme-handler/unknown" = [ "firefox.desktop" ];
      };
    };

    # NOTE: autostart/.desktop entries for the third-party apps
    # (kartoza-screencaster, kartoza-timesheet, gatus-monitor) moved out to
    # their own files under software/desktop/ — the cosmic module keeps
    # only cosmic-repo packages and their config.

    # Enable location services
    services.geoclue2.enable = true;

    # Enable fingerprint reader support (required by cosmic-ext-enroll)
    services.fprintd.enable = true;

    # Enable printing support
    services.printing.enable = true;

    # Enable Avahi for network discovery (printers, etc.)
    services.avahi = {
      enable = true;
      nssmdns4 = true;
    };

    # Enable automounting for removable media
    services.udisks2.enable = true;
    services.gvfs.enable = true;

    # Allow active wheel users to perform udisks2 disk operations
    # (format, restore image, etc.) without an interactive auth_admin
    # prompt. COSMIC's polkit agent (cosmic-osd) does not reliably
    # complete these prompts, causing GNOME Disks to fail with
    # "Not authorized to perform operation (udisks-error-quark, 4)".
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id.indexOf("org.freedesktop.udisks2.") == 0 &&
            subject.isInGroup("wheel") &&
            subject.active) {
          return polkit.Result.YES;
        }
      });
    '';

    # Font configuration for crisp rendering
    fonts.fontconfig = {
      enable = true;
      defaultFonts = {
        sansSerif = [ "Fira Sans" ];
        serif = [ "Noto Serif" ];
        monospace = [ "JetBrains Mono" ];
      };
      subpixel = {
        rgba = "rgb";
        lcdfilter = "default";
      };
      hinting = {
        enable = true;
        style = "slight";
      };
      antialias = true;
    };

    # Lid switch behavior
    services.logind.settings.Login = {
      HandleLidSwitch = "suspend";
      HandleLidSwitchExternalPower = "suspend";
    };

    # Qt theming - use COSMIC-compatible settings
    qt = {
      enable = true;
      platformTheme = lib.mkDefault "gnome";
      style = lib.mkDefault "adwaita";
    };
  };
}
