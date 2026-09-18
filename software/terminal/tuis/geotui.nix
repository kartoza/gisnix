{ config, pkgs, ... }:
{

  # GeoTUI - Midnight Commander-style TUI for GeoServer management
  # See https://github.com/kartoza/geotui
  environment.systemPackages = with pkgs; [
    geotui
  ];

}
