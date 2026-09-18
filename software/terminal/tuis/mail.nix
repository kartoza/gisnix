# Terminal mail.
#
# aerc, for reading mail without leaving the terminal. desktop-productivity
# carries the graphical client; this is the counterpart for a host that has
# no desktop, or for anyone who would rather not use one.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    aerc
  ];
}
