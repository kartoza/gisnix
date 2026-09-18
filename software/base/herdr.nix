{ ... }:
{
  # herdr itself is installed by base/utilities.nix; this module only deploys
  # its keybindings.
  #
  # Single source of truth in /etc/xdg/herdr/, symlinked into each user's
  # ~/.config/herdr/ because that is the only path herdr reads. Mirrors
  # software/terminal/tuis/yazi.nix and software/base/kitty.nix.
  environment.etc."xdg/herdr/config.toml" = {
    mode = "0444";
    source = ../../dotfiles/herdr/config.toml;
  };

  system.activationScripts.herdrConfig = ''
    for dir in /home/*; do
      user="$(basename "$dir")"
      if id "$user" &>/dev/null && [ -d "$dir" ]; then
        mkdir -p "$dir/.config/herdr"
        ln -sf /etc/xdg/herdr/config.toml "$dir/.config/herdr/config.toml"
        chown -h "$user":"$(id -gn "$user")" \
          "$dir/.config/herdr" \
          "$dir/.config/herdr/config.toml" 2>/dev/null || true
      fi
    done
  '';
}
