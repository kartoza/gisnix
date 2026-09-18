{ config, pkgs, ... }:
{
  # Set your time zone.
  time.timeZone = "Africa/Johannesburg";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_ZA.UTF-8";
  # Configure keymap in X11
  services.xserver = {
    xkb.layout = "za";
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
