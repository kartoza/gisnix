# Calendar and scheduling applications.
#
# vdirsyncer (CalDAV/CardDAV sync) is deliberately not deployed here: it
# needs a real account config (server, credentials) that is yours to
# write, not something a generic distro can ship a working default for.
# The packages below read from the same ~/.local/share/{calendars,contacts}
# vdirsyncer would populate; install vdirsyncer yourself and point its
# config at /etc/xdg/vdirsyncer/config or ~/.config/vdirsyncer/config
# if you want the sync half too.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    khal # CLI calendar application with CalDAV support for Google Calendar
    khard # console based contacts management
    gcalcli # Command line interface to Google Calendar
  ];

  # Deploy khal configuration to /etc/xdg/khal/config
  # khal checks XDG_CONFIG_DIRS which includes /etc/xdg by default
  environment.etc."xdg/khal/config" = {
    mode = "0644";
    source = ../../../dotfiles/khal/config;
  };

  # Deploy khard configuration to /etc/xdg/khard/khard.conf, then symlink
  # it into every user's ~/.config/khard/khard.conf.
  #
  # UNLIKE khal, khard does NOT search XDG_CONFIG_DIRS — verified against
  # its own source (khard/config.py): it only ever checks
  # $XDG_CONFIG_HOME/khard/khard.conf (default ~/.config/khard/khard.conf),
  # with no /etc/xdg fallback. The comment this replaced claimed otherwise
  # and was never true; khard has been unable to find its config on every
  # host that carries this module until now — `khard` with no args fails
  # "Config file not found: ~/.config/khard/khard.conf" regardless of what
  # is deployed to /etc/xdg. The symlink is the same pattern herdr.nix and
  # kitty.nix already use for exactly this class of app.
  environment.etc."xdg/khard/khard.conf" = {
    mode = "0644";
    source = ../../../dotfiles/khard/config;
  };
  system.activationScripts.khardConfig = ''
    for dir in /home/*; do
      user="$(basename "$dir")"
      if id "$user" &>/dev/null && [ -d "$dir" ]; then
        mkdir -p "$dir/.config/khard"
        ln -sf /etc/xdg/khard/khard.conf "$dir/.config/khard/khard.conf"
        chown -h "$user":"$(id -gn "$user")" \
          "$dir/.config/khard" \
          "$dir/.config/khard/khard.conf" 2>/dev/null || true
      fi
    done
  '';
}
