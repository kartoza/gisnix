# SPDX-FileCopyrightText: Tim Sutton
# SPDX-License-Identifier: MIT
#
# Generate networking.extraHosts for every machine in the fleet, identically
# on every machine in the fleet.
#
# Why: `ssh anyhost` should work from any host this flake manages, without
# depending on whether the overlay network happens to be up. Until now each
# hosts/*/networking.nix carried its own hand-written extraHosts block. A
# dozen copies, maintained by hand, had already drifted — one host still
# pointed at a stale Tailscale address for another, that other host did not
# know about the first at all, and the entries for people's own laptops
# appeared on some hosts and not others.
#
# hosts/fleet.nix is now the only place those facts live. A host with
# lanAddress = null contributes nothing, which is correct: the roaming laptops
# have no stable address to publish, and once they are on the NetBird overlay
# their names resolve through NetBird's DNS instead.
#
# This is deliberately *additive*. networking.extraHosts is a plain string, so
# a host that needs a private entry can still append its own; nothing here
# forces or overrides.

{ lib, fleet, ... }:

let
  # `fleet` arrives via specialArgs (see flake.nix's mkHost) rather than
  # being imported from a `../../../hosts/fleet.nix` path here: this module
  # is shared, bundle-driven infrastructure that every host takes the same
  # copy of, but the fleet registry it describes is repo-specific — a
  # downstream flake that pins gisnix as an input has its OWN fleet.nix, not
  # this one.

  # Managed hosts and unmanaged peers are published the same way; the
  # distinction matters for deployment, not for name resolution.
  everything = fleet.hosts // fleet.peers;

  # Only entries that actually have an address to publish.
  addressed = lib.filterAttrs (_: h: h.lanAddress or null != null) everything;

  # "192.168.1.10 myserver" — plus any aliases on the same line, which is how
  # /etc/hosts expects multiple names for one address.
  entryFor =
    name: h:
    let
      names = [ name ] ++ (h.aliases or [ ]);
    in
    "${h.lanAddress} ${lib.concatStringsSep " " names}";
in
{
  networking.extraHosts = lib.mkBefore ''
    # ── fleet ────────────────────────────────────────────────────────────
    # Generated from hosts/fleet.nix by
    # software/services/system/fleet-hosts.nix. Do not edit by hand: add or
    # change the host in the registry and rebuild.
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList entryFor addressed)}
  '';
}
