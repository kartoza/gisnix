{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Stylix system-wide theming configuration
  # Based on Kartoza brand colors from profiles/kartoza.nix
  #
  # Kartoza Colors:
  #   highlight1 = "#DF9E2F" (yellow/orange - primary accent)
  #   highlight2 = "#569FC6" (blue - secondary accent)
  #   highlight3 = "#8A8B8B" (grey)
  #   highlight4 = "#06969A" (teal)
  #   alert = "#CC0403" (red)
  #
  # NOTE: Many apps are manually themed with Kartoza colors in dotfiles/
  # Stylix is configured to NOT override those custom themes.

  stylix = {
    enable = true;

    # Use Kartoza wallpaper
    image = ../resources/kartoza-wallpaper.png;

    # Dark theme to match existing Breeze Dark setup
    polarity = "dark";

    # Custom Kartoza base16 color scheme
    # Based on base16 format: https://github.com/tinted-theming/home
    base16Scheme = {
      # Base colors (backgrounds and foregrounds)
      base00 = "1a1a1a"; # Default Background (dark grey/black)
      base01 = "2d2d2d"; # Lighter Background
      base02 = "3d3d3d"; # Selection Background
      base03 = "8a8b8b"; # Comments, Invisibles (Kartoza grey)
      base04 = "b0b0b0"; # Dark Foreground
      base05 = "e0e0e0"; # Default Foreground
      base06 = "f0f0f0"; # Light Foreground
      base07 = "ffffff"; # Light Background

      # Accent colors (mapped from Kartoza brand)
      base08 = "cc0403"; # Red (Kartoza alert)
      base09 = "df9e2f"; # Orange (Kartoza highlight1 - primary accent)
      base0A = "dfb02f"; # Yellow (variation of highlight1)
      base0B = "06969a"; # Green/Teal (Kartoza highlight4)
      base0C = "569fc6"; # Cyan/Blue (Kartoza highlight2)
      base0D = "569fc6"; # Blue (Kartoza highlight2)
      base0E = "9a6ac7"; # Purple (complement to teal)
      base0F = "df9e2f"; # Brown/Orange (Kartoza highlight1)
    };

    # Font configuration matching KDE Plasma setup
    fonts = {
      sansSerif = {
        package = pkgs.noto-fonts;
        name = "Noto Sans";
      };
      serif = {
        package = pkgs.noto-fonts;
        name = "Noto Serif";
      };
      monospace = {
        package = pkgs.jetbrains-mono;
        name = "JetBrains Mono";
      };
      emoji = {
        package = pkgs.noto-fonts-color-emoji;
        name = "Noto Color Emoji";
      };
      sizes = {
        applications = 10;
        desktop = 10;
        popups = 10;
        terminal = 11;
      };
    };

    # Cursor theme - keep Hackneyed from existing config
    cursor = {
      package = pkgs.hackneyed;
      name = "Hackneyed";
      size = 24;
    };

    # Opacity settings for a sleek look
    opacity = {
      applications = 1.0;
      desktop = 1.0;
      popups = 0.95;
      terminal = 0.92;
    };

    # Stylix auto-enables targets based on what's installed
    # We disable targets for apps that have custom Kartoza theming

    # Disable NixOS-level targets that conflict with existing Kartoza theming
    targets = {
      # Keep custom Kartoza plymouth theme (software/services/system/kartoza-plymouth-theme.nix)
      plymouth.enable = false;

      # Keep custom Kartoza GRUB theme (software/services/system/kartoza-grub-theme.nix)
      grub.enable = false;

      # Keep the Kartoza console palette from tty-fonts-common.nix as
      # the single source of console.colors.  If Stylix also drives
      # console.colors, its base16 values get list-concatenated with
      # ours and the kernel command line ends up with 32 comma values
      # in vt.default_red/grn/blu — overflowing the kernel's 16-arg
      # limit and printing errors on TTY (visible around frame 54 of
      # the boot-hardware recording).
      console.enable = false;

      # GTK theming - let Stylix handle this
      gtk.enable = true;
    };
  };

  # Configure home-manager Stylix targets
  # Disable targets for apps with manual Kartoza theming
  home-manager.sharedModules = [
    {
      stylix.targets = {
        # Disable xresources (not needed on pure Wayland, causes build errors)
        xresources.enable = lib.mkForce false;

        # Keep custom starship config (dotfiles/starship.toml has Kartoza colors)
        starship.enable = lib.mkForce false;

        # Keep custom yazi theme (dotfiles/yazi/theme.toml has Kartoza colors)
        yazi.enable = lib.mkForce false;

        # Keep custom lazygit config (dotfiles/lazygit/config.yml has Kartoza colors)
        lazygit.enable = lib.mkForce false;

        # Keep custom kitty config if you have one
        kitty.enable = lib.mkForce false;

        # Keep custom fish config (dotfiles/fish/config.fish)
        fish.enable = lib.mkForce false;

        # Keep custom bat config if present
        bat.enable = lib.mkForce false;

        # Let Stylix theme these (no custom configs):
        # gtk, qt, foot, fzf, etc.
      };
    }
  ];
}
