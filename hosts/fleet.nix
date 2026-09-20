# SPDX-License-Identifier: MIT
#
# THE FLEET REGISTRY — one entry per machine this flake knows about.
#
# This is the single source of truth for host *metadata*. The NixOS
# configuration of a host lives in hosts/<name>/; what the fleet knows ABOUT
# that host lives here, because several things need it at once:
#
#   flake.nix                     -> allHosts, and therefore every
#                                    nixosConfiguration, VM and check
#   software/services/system/
#     fleet-hosts.nix             -> networking.extraHosts, generated
#                                    identically on every host so any
#                                    machine can `ssh <anyhost>`
#   utils/lib/fleet.sh            -> the operator commands: which user to
#                                    SSH as, where the machine is, how it
#                                    deploys, how to wake or unlock it
#
# The file exports two attrsets:
#
#   hosts  machines this flake builds and deploys. attrNames of this is
#          allHosts in flake.nix, so adding an entry here — with a matching
#          hosts/<name>/ directory — is all it takes to mint a host.
#   peers  machines you want NAMES for but do not manage: other people's
#          machines, the router. They get /etc/hosts entries; nothing is
#          ever deployed to them.
#
# Fields on a host
#   description    human-readable summary; shown by inventory and the docs.
#   role           "workstation" — a desktop someone sits in front of
#                  "server"      — headless, always on
#                  "test"        — throwaway, exists for QEMU iteration
#   owner          who uses it day to day. Metadata only.
#   sshUser        account the operator commands SSH as.
#   lanAddress     IPv4 on the local network, or null if it has no fixed
#                  address (roaming laptops). null hosts are simply omitted
#                  from extraHosts — that records "no stable address", which
#                  is the truth, rather than an oversight.
#   aliases        extra names pointing at lanAddress in /etc/hosts.
#   macAddress     wired NIC MAC, for wake-on-LAN, or null if the host is not
#                  woken remotely.
#   initrdSshPort  port the initrd SSH daemon listens on for remote
#                  unlock/reboot — every host gets one by default (see
#                  software/base/initrd-ssh-unlock.nix), null only for a
#                  host that opted out in its own config.nix.
#   deploy         "local"  — rebuild in place, on the machine itself
#                  "ssh"    — build here, sign, copy the closure, activate
#                             there. For hosts that should not build.
#                  "rsync"  — copy the working tree over, then build there.
#                  "none"   — not deployed; VM only.
#
# gisnix ships one example host, used by the installer, the docs, and
# `nix run .#example-vm`. Add your own machine's entry (and a matching
# hosts/<name>/ directory) alongside it.

{
  hosts = {
    example = {
      description = "Example host — installer target, ZFS-encrypted single disk, minimal base + COSMIC";
      role = "test";
      owner = "you";
      sshUser = "nixos";
      lanAddress = null;
      aliases = [ ];
      macAddress = null;
      initrdSshPort = 2222;
      deploy = "none";
    };
  };

  peers = { };
}
