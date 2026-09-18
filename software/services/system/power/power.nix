{ pkgs, lib, ... }:
let
  batteryMonitorScript = pkgs.writeShellApplication {
    name = "battery-monitor";
    runtimeInputs = with pkgs; [
      coreutils
      libnotify
      systemd
    ];
    text = builtins.readFile ../../../../dotfiles/scripts/battery-monitor.sh;
  };
in
{
  # Enable power management - only useful
  # if you have a laptop or a device that needs
  # power management
  services.upower = {
    enable = true;
    # Thresholds for upower daemon (backup to our custom monitor)
    # Our custom battery-monitor service handles:
    # - 10%: Alert user (critical battery warning, bypasses DND)
    # - 5%: Suspend the laptop
    # - 3%: Shutdown the laptop
    percentageLow = 10;
    percentageCritical = 5;
    percentageAction = 3;
    criticalPowerAction = "PowerOff";
  };

  # Custom battery monitoring script package
  environment.systemPackages = [ batteryMonitorScript ];

  # Battery monitor systemd service for tiered warnings
  # - 10%: Alert user (critical battery warning, bypasses DND)
  # - 5%: Suspend the laptop
  # - 3%: Shutdown the laptop
  # Uses critical urgency to bypass DND
  systemd.user.services.battery-monitor = {
    description = "Battery monitor with tiered warnings";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${batteryMonitorScript}/bin/battery-monitor";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
  # Make the device suspend when the power button is pressed
  services.logind = {
    settings = {
      Login = {
        HandlePowerKey = "suspend";
        HandleSwitchExternalPower = "suspend";
        HandleSwitchDocked = "ignore";
        HandleLidSwitch = "suspend";
        HandleLidSwitchDocked = "ignore";
      };
    };
  };
}
