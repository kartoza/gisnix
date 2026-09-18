{
  config,
  pkgs,
  lib,
  ...
}:
{
  # Set your time zone.
  time.timeZone = lib.mkForce "Africa/Nairobi";

  # Select internationalisation properties.
  i18n.defaultLocale = lib.mkForce "en_GB.UTF-8";

  # Select internationalisation properties.
  i18n.extraLocaleSettings = {
    LC_ADDRESS = lib.mkForce "en_GB.UTF-8";
    LC_IDENTIFICATION = lib.mkForce "en_GB.UTF-8";
    LC_MEASUREMENT = lib.mkForce "en_GB.UTF-8";
    LC_MONETARY = lib.mkForce "en_GB.UTF-8";
    LC_NAME = lib.mkForce "en_GB.UTF-8";
    LC_NUMERIC = lib.mkForce "en_GB.UTF-8";
    LC_PAPER = lib.mkForce "en_GB.UTF-8";
    LC_TELEPHONE = lib.mkForce "en_GB.UTF-8";
    LC_TIME = lib.mkForce "en_GB.UTF-8";
  };

  # Configure keymap in X11
  services.xserver = {
    xkb.layout = lib.mkForce "us";
    xkb.variant = "";
  };

  # Configure console keymap
  console.keyMap = "pt-latin1";

  # Add system wide packages
  environment.systemPackages = with pkgs; [
    aspell
    aspellDicts.uk
  ];
}
