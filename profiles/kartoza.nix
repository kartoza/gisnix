{
  config,
  lib,
  pkgs,
  hostConfig,
  ...
}:
let
  # The palette lives in ../brand.nix, as pure data, so the docs and any
  # future service theme read the same five numbers this module does. It used
  # to be defined here, where nothing outside the module system could see it
  # and the documentation quoted the hex codes by hand.
  brand = import ../brand.nix;
  kartozaColors = brand.colors;

  # Centralized theming configuration
  kartozaTheme = {
    # Icon theme - Papirus supports color customization and has excellent coverage
    # The teal and blue colors align well with Kartoza's brand
    iconTheme = {
      name = "Papirus";
      nameDark = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
  };
in
{
  # Export Kartoza colors for use in other modules
  options.kartoza.colors = lib.mkOption {
    type = lib.types.attrs;
    default = kartozaColors;
    description = "Kartoza core accent colors.";
  };

  # Export Kartoza theme settings for use in other modules
  options.kartoza.theme = lib.mkOption {
    type = lib.types.attrs;
    default = kartozaTheme;
    description = "Kartoza theming configuration (icon theme, etc).";
  };

  config = {
    kartoza.colors = kartozaColors;
    kartoza.theme = kartozaTheme;

    # Install icon theme and Kartoza tools system-wide.
    # NOTE: kartoza-timesheet and kartoza-screencaster moved to the
    environment.systemPackages = [
      kartozaTheme.iconTheme.package
    ]
    ++ [
      pkgs.nixos-utils
      pkgs.baboon
    ];

    # Deploy wallpaper resources to /etc for desktop environments
    environment.etc."kartoza-wallpaper.png" = {
      mode = "0444";
      source = ../resources/kartoza-wallpaper.png;
    };

    # SVG version available for apps that support vector graphics
    environment.etc."kartoza-wallpaper.svg" = {
      mode = "0444";
      source = ../resources/kartoza-logo.svg;
    };

    environment.etc."qgis-wallpaper.png" = {
      mode = "0444";
      source = ../resources/qgis-wallpaper.png;
    };

    environment.etc."kartoza-background.gdm.png" = {
      mode = "0444";
      source = ../resources/kartoza-wallpaper.png;
    };

    environment.etc."qgis-background.gdm.png" = {
      mode = "0444";
      source = ../resources/qgis-background.gdm.png;
    };

    # Kartoza start button logo
    environment.etc."kartoza-start-button.png" = {
      mode = "0444";
      source = ../resources/kartoza-start-button.png;
    };

    # SVG version for higher quality at larger sizes
    environment.etc."kartoza-start-button.svg" = {
      mode = "0444";
      source = ../resources/kartoza-logo.svg;
    };
  };
}
