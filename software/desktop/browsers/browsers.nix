# Web browsers.
#
# Split out of desktop/productivity/gui-apps.nix so that browsers are a
# first-class group: they are the one desktop category a host may need on its
{ pkgs, ... }:
{
  # google-chrome is nixpkgs' one unfree package in this bundle (brave,
  # firefox, and ungoogled-chromium are all free). Contributed to the
  # shared allow-list in software/services/system/unfree.nix rather than
  # set here directly — see that file for why.
  kartoza.unfreePackages = [ "google-chrome" ];

  environment.systemPackages = with pkgs; [
    brave
    firefox
    google-chrome
    ungoogled-chromium
  ];
}
