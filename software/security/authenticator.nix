# GNOME Authenticator — TOTP and 2FA codes.
#
# Grouped with the other credential tools rather than with office software,
# which is where it used to live. seahorse, the keyring manager, is NOT here:
# it comes with the COSMIC ssh-agent configuration in
# ../desktop/environments/cosmic/ssh-gpg.nix, which is the module that has an
# opinion about which agent holds your keys.

{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.authenticator ];
}
