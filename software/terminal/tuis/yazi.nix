{ pkgs, ... }:
{
  # the file manager this file configures. It used to be installed by base/utilities.nix, so this
  # bundle shipped configuration for a binary it did not provide.
  environment.systemPackages = with pkgs; [
    yazi
  ];

  # Deploy yazi config to /etc/xdg/yazi/ so we have a single source of
  # truth on disk; the activation script below symlinks it into each
  # user's ~/.config/yazi/ since that's the only place yazi actually
  # reads from. Mirrors the kitty.nix pattern.
  environment.etc."xdg/yazi/yazi.toml" = {
    mode = "0444";
    source = ../../../dotfiles/yazi/yazi.toml;
  };

  environment.etc."xdg/yazi/theme.toml" = {
    mode = "0444";
    source = ../../../dotfiles/yazi/theme.toml;
  };

  # Symlink into each user's ~/.config/yazi/ so yazi picks it up.
  system.activationScripts.yaziConfig = ''
    for dir in /home/*; do
      user="$(basename "$dir")"
      if id "$user" &>/dev/null && [ -d "$dir" ]; then
        mkdir -p "$dir/.config/yazi"
        ln -sf /etc/xdg/yazi/yazi.toml "$dir/.config/yazi/yazi.toml"
        ln -sf /etc/xdg/yazi/theme.toml "$dir/.config/yazi/theme.toml"
        # Remove any plugins dir left over from a previous experiment
        # so a stale smart-enter.yazi symlink doesn't keep firing.
        rm -rf "$dir/.config/yazi/plugins/smart-enter.yazi"
        chown -h "$user":"$(id -gn "$user")" \
          "$dir/.config/yazi" \
          "$dir/.config/yazi/yazi.toml" \
          "$dir/.config/yazi/theme.toml" 2>/dev/null || true
      fi
    done
  '';
}
