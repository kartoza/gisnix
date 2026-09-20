# Remote boot-unlock — a minimal SSH server in the initrd, so a machine
# whose encrypted ZFS root is waiting on a passphrase (or that's just stuck
# partway through boot) can be reached and rebooted from elsewhere. On by
# default for every host: `utils/unlock-host.sh` (the "unlock-host" package
# in utilities.nix) is the client half of this, already ships everywhere.
#
# Deliberately a distinct host key and port, never the system's own sshd —
# the initrd (and this key) live on the unencrypted ESP, so anyone with the
# disk in hand could read the key and impersonate this server. It can only
# ever answer "yes, type the pool passphrase here", which is a much smaller
# thing to have exposed than the real system would be.
{
  config,
  pkgs,
  lib,
  hostConfig,
  ...
}:
let
  # A number, not null, disables this for the one host that genuinely wants
  # no network reachable before its own sshd is up — set
  # `initrdSshPort = null;` in that host's config.nix to opt out.
  port = hostConfig.initrdSshPort or 2222;

  # Every normal user's own keys, not one hardcoded account — a distro
  # can't assume which username the owner picked during install.
  ownerKeys = builtins.concatLists (
    map (u: u.openssh.authorizedKeys.keys) (
      builtins.filter (u: u.isNormalUser) (builtins.attrValues config.users.users)
    )
  );
in
{
  config = lib.mkIf (port != null) {
    boot.initrd.network = {
      enable = true;
      flushBeforeStage2 = false;
      ssh = {
        enable = true;
        inherit port;
        hostKeys = [ "/etc/secrets/initrd/ssh_host_ed25519_key" ];
        authorizedKeys = ownerKeys;
      };
    };

    # Plain DHCP — whatever the machine is plugged into. A host on an
    # unusual NIC that needs its driver forced this early (some do) adds
    # `boot.initrd.kernelModules` in its own hardware.nix; that's real
    # hardware detection, which is out of scope for a module every host
    # shares.
    boot.initrd.systemd.network = {
      enable = true;
      networks."10-ethernet" = {
        matchConfig.Name = "en* eth*";
        networkConfig.DHCP = "yes";
        dhcpV4Config.RouteMetric = 10;
      };
    };

    # ip/ping inside the initrd, for diagnosing an unlock connection that
    # isn't coming up from the machine's own console.
    boot.initrd.systemd.extraBin = {
      ip = "${pkgs.iproute2}/bin/ip";
      ping = "${pkgs.iputils}/bin/ping";
    };

    system.activationScripts.initrd-ssh-key = ''
      if [ ! -f /etc/secrets/initrd/ssh_host_ed25519_key ]; then
        mkdir -p /etc/secrets/initrd
        ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f /etc/secrets/initrd/ssh_host_ed25519_key -N ""
        chmod 600 /etc/secrets/initrd/ssh_host_ed25519_key
      fi
    '';
  };
}
