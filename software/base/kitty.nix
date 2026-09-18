{ pkgs, ... }:
{
  # Set KITTY_CONFIG_DIRECTORY so kitty always finds our config
  # regardless of how it's launched (desktop, terminal, etc.)
  environment.variables.KITTY_CONFIG_DIRECTORY = "/etc/xdg/kitty";

  # Deploy kitty config files to /etc/xdg/kitty/
  environment.etc."xdg/kitty/kitty.conf" = {
    mode = "0444";
    source = ../../dotfiles/kitty.conf;
  };

  environment.etc."xdg/kitty/tab_bar.py" = {
    mode = "0444";
    source = ../../dotfiles/kitty/tab_bar.py;
  };

  environment.etc."xdg/kitty/kartoza-watermark.png" = {
    mode = "0444";
    source = ../../resources/kartoza-watermark.png;
  };

  # Also symlink into ~/.config/kitty/ as a fallback
  system.activationScripts.kittyConfig = ''
    for dir in /home/*; do
      user="$(basename "$dir")"
      if id "$user" &>/dev/null && [ -d "$dir" ]; then
        mkdir -p "$dir/.config/kitty"
        ln -sf /etc/xdg/kitty/kitty.conf "$dir/.config/kitty/kitty.conf"
        ln -sf /etc/xdg/kitty/tab_bar.py "$dir/.config/kitty/tab_bar.py"
        # Remove the retired kanata focus-watcher symlink (polymorphic-base
        # era) and any stale Python bytecode cache
        rm -f "$dir/.config/kitty/kanata-app-layer.py"
        rm -rf "$dir/.config/kitty/__pycache__"
        chown -h "$user":"$(id -gn "$user")" "$dir/.config/kitty/kitty.conf" "$dir/.config/kitty/tab_bar.py"
      fi
    done
  '';
}
