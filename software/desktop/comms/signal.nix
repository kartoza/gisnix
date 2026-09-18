# Signal Desktop — messaging app. Wrapped via overlay to use kwallet6 for
# credential storage. Not a COSMIC-repo package, so it lives in the generic
# desktop-apps collection (previously bundled in the cosmic module as
# "standard for all COSMIC users"). Slim-gated.
{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.signal-desktop ];
}
