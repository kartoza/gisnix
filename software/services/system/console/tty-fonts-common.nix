{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Console configuration for better readability and emoji support
  console = {
    # Use UniFont for Unicode and emoji support in TTY
    font = "ter-132n"; # Terminus font, size 32, normal weight
    # Alternative Unicode fonts:
    # font = "Uni3-Terminus28x14"; # UniFont 28x14
    # font = "Uni3-Terminus24x12"; # UniFont 24x12
    # font = "Uni3-Terminus20x10"; # UniFont 20x10
    # Standard fallback fonts (no emoji support):
    # font = "ter-132n"; # Terminus font, size 32, normal weight
    # font = "ter-124n"; # Terminus 24
    # font = "latarcyrheb-sun32"; # Fallback option

    # Early setup - this ensures the font is loaded as early as possible
    earlySetup = true;

    # Ensure console fonts are properly available to the console subsystem
    packages = with pkgs; [
      terminus_font
      kbd # Provides console font utilities
      unifont # Contains Unicode symbols and emojis
    ];

    # Kartoza color scheme for TTY
    # Press crtl+alt+F1..F6 to switch to TTY consoles to see the effect
    colors = [
      "1F1F1F" # base03 (dark background)
      "ebb144" # red (mapped to orange-red tone)
      "ecb44b" # green (mapped to yellow-greenish)
      "f0b643" # yellow
      "57a0c7" # blue
      "c13022" # magenta
      "efebea" # cyan
      "ffffff" # base2 (light foreground)
      "d1cece" # base03 (secondary dark background)
      "ebb144" # orange
      "efeae9" # base01
      "f0eceb" # base00
      "eeeae9" # base0
      "7a1d15" # violet
      "fdfcfc" # base1
      "f1eeed" # base3 (light background)
    ];
  };

  # Configure fonts for fbterm to support powerline/starship
  fonts = {
    packages = with pkgs; [
      # Powerline fonts
      powerline-fonts

      # Nerd Fonts (individual packages)
      nerd-fonts.dejavu-sans-mono
      nerd-fonts.fira-code
      nerd-fonts.hack
      nerd-fonts.jetbrains-mono
      nerd-fonts.caskaydia-mono
      nerd-fonts.caskaydia-cove
      nerd-fonts.caskaydia-mono

      # Core fonts for better Unicode support
      dejavu_fonts
      liberation_ttf

      # Emoji and Unicode support
      unifont
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      twitter-color-emoji
    ];

    # Enable font directory for applications
    fontDir.enable = true;
  };

  # Ensure gpm (mouse daemon) is enabled for tty mouse support
  services.gpm.enable = true;

  # Add fbterm group and permissions for advanced TTY features
  users.groups.fbterm = { };

  # Set console keyMap to support Unicode input
  console.keyMap = lib.mkDefault "us";

}
