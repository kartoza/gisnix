{ pkgs, lib, ... }:

{
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
  };

  # Steam and its runtime are unfree; allow-list the names programs.steam pulls
  # in or a host taking desktop-games fails to evaluate. See
  # software/services/system/unfree.nix. If a name here is wrong or another is
  # needed, the all-bundles eval check (utils/check-bundle-eval.sh) names it.
  kartoza.unfreePackages = [
    "steam"
    "steam-unwrapped"
  ];
}
