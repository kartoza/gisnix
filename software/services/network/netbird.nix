{ pkgs, ... }:

{
  # make the netbird command usable to users
  environment.systemPackages = [
    pkgs.netbird
  ];

  # enable the netbird service (creates the wt0 interface — see
  # software/services/system/ssh-access.nix, which already allows it)
  services.netbird.enable = true;

  networking.firewall.allowedUDPPorts = [ 51820 ];
  networking.firewall.checkReversePath = "loose";

  # Now configure from the command line like this:
  # systemctl status netbird

  # Finally, perform an initial authentication for this machine and you're done.
  # sudo netbird up

  # Validate:
  # ip link show wt0
  # journalctl -fu netbird
}
