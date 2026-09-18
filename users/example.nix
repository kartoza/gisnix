# Example user — the installer writes one of these per machine, named for
# the account it creates. Copy this file for a hand-rolled host (`kz
# create-host` does it for you), rename it, and fill in a real SSH key.
{ pkgs, ... }:
{
  users.users.example = {
    isNormalUser = true;
    description = "Example User";
    extraGroups = [ "wheel" ];
    shell = pkgs.bash;

    # Paste your own public key(s) here — an empty list means password-only
    # login, which is fine for a first boot but should not stay that way.
    openssh.authorizedKeys.keys = [ ];
  };
}
