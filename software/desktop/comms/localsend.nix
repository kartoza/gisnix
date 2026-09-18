{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    localsend
  ];
  # Open network ports
  networking.firewall.allowedTCPPorts = [ 53317 ];
  networking.firewall.allowedUDPPorts = [ 53317 ];
  # Example of doing it for a specific interface
  networking.firewall.interfaces."kartoza-vpn".allowedTCPPorts = [ 53317 ];
  networking.firewall.interfaces."kartoza-vpn".allowedUDPPorts = [ 53317 ];
}
