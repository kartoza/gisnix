# Several modules (kitty.nix, herdr.nix, yazi.nix, calendar.nix, and any
# future one following the same pattern) deploy dotfiles via
# system.activationScripts doing `mkdir -p "$dir/.config/<app>"` as root, then
# chown only the leaf file or directory they just created — never the
# `.config` directory itself. `mkdir -p` creates missing parents too, so the
# FIRST such script to run on a fresh install creates `~/.config` owned by
# root, and every other script's own chown never reaches back to fix that
# parent.
#
# The result is invisible until something else needs to create a NEW
# subdirectory under `~/.config` for the first time — which is exactly what
# a first login does: cosmic-comp, cosmic-greeter and cosmic-theme all
# create their own config directories there, as the real user, and get
# `Permission denied` doing it. Confirmed against a real install: cosmic-comp
# panicking in `Config::load` with EACCES, cosmic-greeter-daemon logging the
# same for half a dozen of its own config/theme handlers, `.config` itself
# owned root:root while a sibling directory one of the per-app scripts DID
# chown (herdr) was fine.
#
# Fixed centrally rather than patching every per-app script (and every
# future one that will make the same mistake): chowning just the `.config`
# directory itself is safe and order-independent regardless of whether this
# runs before or after any per-app script — none of them touch `.config`'s
# own ownership, only its contents, and mkdir -p is idempotent either way.
{ ... }:
{
  system.activationScripts.userConfigOwnership = ''
    for dir in /home/*; do
      user="$(basename "$dir")"
      if id "$user" &>/dev/null && [ -d "$dir" ]; then
        mkdir -p "$dir/.config"
        chown "$user":"$(id -gn "$user")" "$dir/.config"
      fi
    done
  '';
}
