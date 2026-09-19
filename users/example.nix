# Example user — the installer writes one of these per machine, named for
# the account it creates. Copy this file for a hand-rolled host (`gisnix
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

  # kanata (services-device-input-kanata, on by default) writes remapped
  # keystrokes through /dev/uinput — every user needs this group membership
  # for it to work, not just the account it happens to be declared next to.
  users.groups.uinput.members = [ "example" ];

  # Uncomment to have the kanata herdr layer's `e` key (hold Caps Lock —
  # see docs/user/keyboard.md) type this address for you. Leave it out and
  # the key stays silent; nothing else about the account changes either way.
  # kartoza.userEmails.example = "you@example.com";
}
