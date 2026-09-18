{ config, pkgs, ... }:

{

  ##
  ## iPhone Support
  ##

  environment.systemPackages = with pkgs; [
    libimobiledevice # Iphone support
    ifuse # optional, to mount using 'ifuse' for iPhone
  ];

  services.usbmuxd.enable = true;

}
