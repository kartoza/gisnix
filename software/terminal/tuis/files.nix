# File and disk browsers.
#
# Full-screen, keyboard-driven ways of looking at a filesystem. They were in
# base/utilities.nix, which is where every command-line tool had ended up
# regardless of shape — so the bundle whose description promises "file
# manager" installed none, and a host taking terminal-tuis got yazi's
# configuration without yazi.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    dua # interactive disk usage, `dua i`
    mc # Midnight Commander
    ncdu # disk usage, ncurses
  ];
}
