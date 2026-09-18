{ pkgs, ... }:
{
  # the git interface this file configures. It used to be installed by base/utilities.nix, so this
  # bundle shipped configuration for a binary it did not provide.
  environment.systemPackages = with pkgs; [
    lazygit
  ];

  # Deploy lazygit config with Kartoza theme to /etc
  # Users will have XDG_CONFIG_DIRS include /etc/xdg automatically
  # so lazygit will find the config at /etc/xdg/lazygit/config.yml
  environment.etc."xdg/lazygit/config.yml" = {
    mode = "0444";
    source = ../../../dotfiles/lazygit/config.yml;
  };

  # lazygit is already installed in utilities.nix
  # This module only handles the configuration deployment
}
