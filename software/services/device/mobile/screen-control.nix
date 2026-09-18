{ config, pkgs, ... }:

{

  # DDCControl is used to adjust brightness etc of your external
  # monitor. Use the gddccontrol gui app to configure things.

  # We need to add some kernel module and the users using the app
  # need to be in the ic2 group.

  # See https://discourse.nixos.org/t/how-to-enable-ddc-brightness-control-i2c-permissions/20800
  # And https://github.com/ddccontrol/ddccontrol

  # I think this makes the lines below redundant
  hardware.i2c.enable = true;

  boot.kernelModules = [ "i2c-dev" ];
  services.udev.extraRules = ''
    KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"
  '';
  # Add system wide packages
  environment.systemPackages = with pkgs; [
    ddccontrol
    ddcutil
  ];

}
