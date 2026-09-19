# Who is allowed to reach sshd — the local network and the overlay VPN, never
# the open internet.
#
# THE POSTURE
#
# ssh.nix already refuses passwords and root logins, so an exposed port 22 is
# not a way in. It is still a way to be found: it answers every scan, banners
# the host, and turns any future OpenSSH advisory into an emergency rather
# than a Tuesday. The port should simply not be reachable from off-network.
#
# Turning this on means the machine is reachable:
#
#   * from `lanRanges` — the RFC1918 networks it sits on, and
#   * over `overlayInterfaces` — the VPN, wherever the operator happens to be.
#
# Nothing else. `services.openssh.openFirewall` is switched off, so the blanket
# "port 22 from anywhere" rule that NixOS adds by default is gone, and these
# two narrower allowances replace it.
#
# WHY IT IS OPT-IN
#
# Because getting it wrong on a machine in another country is unrecoverable.
# Several hosts in a fleet are typically colleagues' laptops with no fixed
# address and no console you can reach; if the overlay is not up on one of
# them when this lands, that host is gone for good. So each host opts in,
# and only after you have confirmed how you actually reach it.
#
#   the machine you develop on   on, worst case is a walk to the desk
#   anything on the same LAN     on, physically reachable
#   the rest                     off, pending a working overlay enrolment
#
# THE ONE THAT MATTERS
#
# A host with no overlay at all — no tailscale, no NetBird, no LAN address in
# hosts/fleet.nix — and a networking.nix that opens port 22 to the world is
# reached, today, across the open internet by whatever finds it. That host
# needs an overlay before it can take this, and it is the strongest argument
# for finishing that migration.

{ config, lib, ... }:

let
  cfg = config.kartoza.ssh;
  port = 22;
in
{
  options.kartoza.ssh = {
    restrictToTrustedNetworks = lib.mkEnableOption ''
      limiting sshd to the local network and the overlay VPN.

      Off by default, and deliberately so: a host that is reached over neither
      becomes permanently unreachable the moment this is switched on
    '';

    lanRanges = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "192.168.0.0/16"
        "10.0.0.0/8"
        "172.16.0.0/12"
      ];
      description = ''
        IPv4 source ranges allowed to reach sshd, in CIDR form.

        The default is the three private ranges, which covers every network
        the fleet sits on — 192.168.x here, and the 10.100.x overlay
        addresses inherited from the Tailscale era. Narrow it per host if
        that host's network is known and fixed.
      '';
    };

    overlayInterfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "tailscale0"
        "wt0"
        "kartoza-vpn"
      ];
      example = [ "wt0" ];
      description = ''
        Interfaces on which sshd is reachable regardless of source address —
        the VPN links, which are already authenticated at the tunnel.

        All three are listed because the fleet is mid-migration: `tailscale0`
        is what runs today, `wt0` is NetBird's, and `kartoza-vpn` is the
        WireGuard link to the office. Naming an interface that does not exist
        on this host is harmless; the rule simply never matches. That is what
        lets NetBird arrive without a firewall change following it.
      '';
    };
  };

  config = lib.mkIf cfg.restrictToTrustedNetworks {
    # NixOS opens 22 to all comers when sshd is enabled. That is the rule
    # being replaced, so it has to go first.
    services.openssh.openFirewall = false;

    # Reachable over the VPN links, wherever the operator is.
    networking.firewall.interfaces = lib.genAttrs cfg.overlayInterfaces (_: {
      allowedTCPPorts = [ port ];
    });

    # ...and from the local network, by source address.
    #
    # `networking.firewall` has no source-range option, so these are written
    # directly. extraCommands runs after the port allowances and before the
    # closing reject, which is exactly where an accept rule has to sit;
    # nixos-fw-accept is the chain NixOS uses for "let this through".
    networking.firewall.extraCommands = lib.concatMapStrings (range: ''
      iptables -A nixos-fw -p tcp --dport ${toString port} -s ${range} -j nixos-fw-accept
    '') cfg.lanRanges;
  };
}
