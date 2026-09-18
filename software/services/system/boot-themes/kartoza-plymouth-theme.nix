{ pkgs, ... }:
{
  # Boot splash stuff
  boot.initrd.systemd.enable = true;

  # Console loglevel — 3 suppresses KERN_ERR too, so benign runtime
  # noise like Framework's `ucsi_acpi USBC000:00: GET_CABLE_PROPERTY
  # failed (-5)` doesn't paint the TTY during the plymouth→DM handoff.
  # (Set via the NixOS option, not `loglevel=` in kernelParams: NixOS
  # appends its own `loglevel=${consoleLogLevel}` with `mkAfter`, so a
  # hand-rolled value would be silently overridden by the default 4.)
  boot.consoleLogLevel = 3;

  boot.kernelParams = [
    # Suppresses console text before the password prompt.
    "quiet"

    # Keep udev's own chatter out of the initrd log too — otherwise
    # its notices flash on-screen right before plymouth takes over.
    "rd.udev.log_level=3"

    # Hide systemd's "[  OK  ] Started …" status list so plymouth owns
    # the whole screen from initrd through DM start.
    "systemd.show_status=false"
    "udev.log_level=3"
  ];
  #boot.plymouth.logo = "/boot/kartoza-wallpaper.gif";
  boot.plymouth = {
    enable = true;
    # See flake.nix for where the package is defined
    themePackages = [ pkgs.kartoza-plymouth-theme ];
    # See https://github.com/adi1090x/plymouth-themes
    # for a list of other awesome themes
    #theme = "flame"; # provided by the kartoza-plymouth-theme flake input (see overlays/default.nix)
    theme = "kartoza"; # provided by the kartoza-plymouth-theme flake input (see overlays/default.nix)
    # Or comment out the above two lines and use this:
    # boot.plymouth.theme = "breeze"; # default is bgrt which shows manufacturer logo
  };
}
