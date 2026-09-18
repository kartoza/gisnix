{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.rustdeskSupport;
in
{
  options.services.rustdeskSupport.uinputUsers = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Users granted access to /dev/uinput for RustDesk's Wayland input injection.";
    example = [ "alice" ];
  };

  config = {
    # RustDesk remote desktop.
    #
    # Wayland support: screen capture goes through xdg-desktop-portal (COSMIC
    # ships its own portal) and input injection through uinput. Attended
    # access works well; unattended access on Wayland is still limited
    # upstream (login-screen access needs X11), so SSH remains the primary
    # remote-admin path.
    #
    # Access model: direct IP access over the tailnet only. RustDesk's
    # direct-access listener (TCP 21118) is opened solely on the tailscale
    # interface — nothing is exposed on LAN or Internet, and no third-party
    # rendezvous server is needed for tailnet peers.
    #
    # Per-user setup (once, in the RustDesk GUI):
    #   Settings → Security → "Allow direct IP access"
    #   Settings → Security → set a strong permanent password
    # Peers connect to the host's tailscale IP/name.

    environment.systemPackages = [ pkgs.rustdesk-flutter ];

    # Wayland input injection
    hardware.uinput.enable = true;
    users.groups.uinput.members = cfg.uinputUsers;

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
      21118 # RustDesk direct IP access
    ];
  };
}
