{
  config,
  pkgs,
  ...
}:
{
  # Set your time zone.
  # See https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
  time.timeZone = "Indian/Antananarivo";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_GB.UTF-8";
  # Configure keymap in X11
  services.xserver = {
    xkb.layout = "us";
    xkb.variant = "";
    xkb.options = "eurosign:e,caps:escape";
  };

  # Configure console keymap
  console.keyMap = "us";

  # Add system wide packages
  environment.systemPackages = with pkgs; [
    aspell
    aspellDicts.uk
  ];
}
