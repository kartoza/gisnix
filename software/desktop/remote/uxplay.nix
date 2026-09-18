{
  pkgs,
  config,
  ...
}:
{
  # Note:
  #
  # You need to pass the -p option so that the allowed ports
  # opened on the firewall below are used by uxplay when it runs
  #
  # We make an alias below for convenient launching

  programs.fish.shellAliases = {
    ux = "uxplay -m -reset 5 -nohold -n Nixos -nh -p";
  };
  environment.systemPackages = with pkgs; [
    uxplay
  ];
  # Open network ports
  networking.firewall.allowedTCPPorts = [
    7000
    7001
    7100
  ];
  networking.firewall.allowedUDPPorts = [
    5353
    6000
    6001
    7011
  ];
  # Example of doing it for a specific interface
  #networking.firewall.interfaces."eth0".allowedTCPPorts = [7000 7001 7100];
  #networking.firewall.interfaces."eth0".allowedUDPPorts = [5353 6000 6001 7011];

  # To enable network-discovery
  # see software/services/network/avahi.nix
}
