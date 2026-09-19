# Latest kernel: 7.2, with the OpenZFS that supports it, both from
# nixpkgs-master.
#
# WHY BOTH HALVES COME FROM ONE SET
#
# Every host here boots from an encrypted ZFS root. NixOS resolves the ZFS
# module as boot.kernelPackages.${boot.zfs.package.kernelModuleAttribute}, so
# taking the kernel from master while leaving ZFS on the pinned nixpkgs gives
# you a pair that does not build — and a machine that cannot unlock or import
# its own pool is not a degraded machine, it is a brick with a rollback.
#
# WHY MASTER AT ALL
#
# OpenZFS 2.4.4 is the first release supporting the 7.x series, and only
# master has it. The pinned nixpkgs, nixpkgs-unstable and nixos-unstable all
# ship 2.4.3, whose ceiling is kernel 7.0 (kernelMaxSupportedMajorMinor =
# "7.0", compared with versionAtLeast, so 7.0 passes and 7.1 does not).
#
# WHAT IT COSTS
#
# master is pre-Hydra, so neither the kernel nor the ZFS module is in
# cache.nixos.org: both compile on the machine, and again whenever the master
# pin moves. master is also a moving branch — a flake.lock update can land a
# kernel/ZFS pair nobody has run yet. Rollback is the previous generation in
# GRUB, which carries its own matching pair.
#
# `gisnix configure` says all of this before the choice is made, not after.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  masterPkgs = import inputs.nixpkgs-master {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = false;
  };
  wanted = masterPkgs.linuxPackages_7_2;
in
{
  # mkDefault so a host may refine the choice without contradicting it. A host
  # with an out-of-tree module that needs patching for this kernel — openrazer
  # against 7.2, say — takes this bundle like anyone else, then swaps in the
  # same kernel set with the patch applied. A plain definition there beats
  # this default.
  boot.kernelPackages = lib.mkDefault wanted;
  boot.zfs.package = lib.mkDefault masterPkgs.zfs_2_4;

  # The mkDefault above is a loaded gun, and this is its safety catch.
  #
  # A host that pins boot.kernelPackages in its own hardware.nix beats
  # mkDefault and keeps its kernel — but nothing overrides the zfs.package
  # line, so the userspace moves to 2.4.4 while the module stays on whatever
  # the pinned kernel set ships. The two halves come apart, which is the one
  # thing this bundle exists to prevent. NixOS then fails with
  #
  #   The kernel module and the userspace tooling versions are not matching
  #
  # which says nothing about the host's own pin being the cause. A host whose
  # hardware.nix pins linuxPackages_6_12 hits exactly that: `kernel = "latest"`
  # produces a 6.12 module against 2.4.4 tooling.
  #
  # Comparing kernel VERSIONS rather than the package set is deliberate: a
  # host may legitimately substitute the same 7.2 set with a patched module,
  # and that must keep working. A refinement of this kernel is fine; a
  # different kernel is not.
  assertions = [
    {
      assertion = config.boot.kernelPackages.kernel.version == wanted.kernel.version;
      message = ''
        This host takes `kernel = "latest"` (kernel ${wanted.kernel.version} +
        OpenZFS ${masterPkgs.zfs_2_4.version} from nixpkgs-master), but
        something else has set boot.kernelPackages to
        ${config.boot.kernelPackages.kernel.version} — a plain assignment in
        the host's hardware.nix beats this module's mkDefault.

        The kernel and the ZFS module must come from one package set, so this
        combination would give you a machine that cannot import its own pool.

        Either drop the boot.kernelPackages pin from the host's hardware.nix
        and let this bundle own the kernel, or set `kernel = "stable"` in the
        host's config.nix and keep the pin.
      '';
    }
  ];
}
