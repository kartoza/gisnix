# Web browsers.
#
# Split out of desktop/productivity/gui-apps.nix so that browsers are a
# first-class group: they are the one desktop category a host may need on its
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    brave
    firefox
    google-chrome
    ungoogled-chromium
  ];
}
