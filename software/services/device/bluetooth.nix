{
  config,
  lib,
  pkgs,
  ...
}:
{
  hardware.bluetooth.enable = true; # enables support for Bluetooth
  hardware.bluetooth.powerOnBoot = lib.mkDefault true; # powers up the default Bluetooth controller on boot

  # Enhanced Bluetooth configuration for better keyboard connectivity
  hardware.bluetooth.settings = {
    General = {
      # Enable experimental features for better device support
      Experimental = true;
      # Keep devices connected
      AutoEnable = true;
      # Faster reconnection
      FastConnectable = true;
    };

    Policy = {
      # Auto-connect to known devices
      AutoEnable = true;
    };
  };

  # Blueman is disabled by default - COSMIC has its own Bluetooth settings
  # Enable per-host in hosts/<hostname>/services.nix if needed
  services.blueman.enable = lib.mkDefault false;
}
