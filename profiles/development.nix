# Only for development. Don't use in production !
{
  config,
  lib,
  pkgs,
  projectConfig,
  hostname,
  ...
}:
lib.throwIfNot (projectConfig.environmentName == "dev")
  ''
    Can't enable insecure development configuration in non-development
    environment !
  ''
  {
    # Add extra packages
    environment.systemPackages = [
      pkgs.htop
      pkgs.jq
      pkgs.tmux
      pkgs.vim
    ];

    # Disable firewall
    networking.firewall.enable = lib.mkForce false;

    # Root user and automatic login
    # Using initialHashedPassword for slightly better security even in dev mode
    # Generated with: mkpasswd -m sha-512 "root"
    users.users.root.initialHashedPassword = "$6$rounds=656000$root$tQC.OJFyUb7r7sEKxnCqKwzUGQCEL6p0ETYB4/9r5x8t8Qx8Hq8Y4HQBVZQNjXqKQPq5e3bBvqG5Z.X8l.Ll71";
    services.openssh.settings.PermitRootLogin = lib.mkForce "yes";
    services.openssh.settings.PasswordAuthentication = lib.mkForce true;
    services.getty.autologinUser = "root";
    virtualisation.vmVariant = {
      # Launch VM in console
      virtualisation.graphics = false;

      # Port forwarding
      virtualisation.forwardPorts = [
        # SSH
        {
          from = "host";
          host.port = 10022;
          guest.port = builtins.elemAt config.services.openssh.ports 0;
        }
        # HTTP
        {
          from = "host";
          host.port = 8080;
          guest.port = 80;
        }
        # HTTPS
        {
          from = "host";
          host.port = 8443;
          guest.port = 443;
        }
      ];
    };

    # Host specific configuration
    imports = [ ../hosts/${hostname}/development.nix ];
  }
