# Social and messaging clients that are not Signal.
#
# Signal has its own module next door because it carries desktop-integration
# quirks; these three are plain installs.

{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    telegram-desktop
    tuba # Mastodon client
    tuisky # Bluesky, in the terminal
  ];
}
