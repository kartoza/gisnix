{ config, pkgs, ... }:
{
  # Configure keymap in X11 and Wayland
  # Multiple layouts with us as default, pt as secondary
  services.xserver = {
    xkb.layout = "us,pt";
    xkb.variant = "";
    # Super+Space to switch layouts. NOT Alt+Shift — kanata's home-row mods
    # emit Alt (s/l) and Shift (f/j), so Alt+Shift toggled the layout by
    # accident mid-typing (silently breaking AltGr symbols / bracket chords).
    xkb.options = "grp:win_space_toggle";
  };
  # Configure console keymap
  console.keyMap = "pt-latin1";

  # Set your time zone.
  time.timeZone = "Europe/Lisbon";

  # This will set the UI language
  i18n.defaultLocale = "en_GB.UTF-8";

  # Select internationalisation properties.
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "pt_PT.UTF-8";
    LC_IDENTIFICATION = "pt_PT.UTF-8";
    LC_MEASUREMENT = "pt_PT.UTF-8";
    LC_MONETARY = "pt_PT.UTF-8";
    LC_NAME = "pt_PT.UTF-8";
    LC_NUMERIC = "pt_PT.UTF-8";
    LC_PAPER = "pt_PT.UTF-8";
    LC_TELEPHONE = "pt_PT.UTF-8";
    LC_TIME = "pt_PT.UTF-8";
  };
  # Add system wide packages
  environment.systemPackages = with pkgs; [
    aspell
    aspellDicts.en
    aspellDicts.uk
    aspellDicts.pt_PT
    libxkbcommon
  ];
}
