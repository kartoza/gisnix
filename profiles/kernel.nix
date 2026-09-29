# Default kernel for a gisnix machine: Linux 7.2, so current hardware
# (recent wifi like the MediaTek MT7925 Wi-Fi 7, AMD Strix Halo graphics
# and NPUs) works out of the box.
#
# mkDefault, so a host that needs something else can pin it in its own
# hardware.nix (a plain assignment) without fighting this. mkDefault (1000)
# also correctly beats nixpkgs' own built-in default for boot.kernelPackages,
# which sits at mkOptionDefault (1500) — do NOT weaken this to mkOptionDefault
# or the two collide ("defined multiple times"). The opt-in
# software/base/kernel/kernel-latest.nix overrides this at a stronger priority
# than mkDefault, so `kernel = "latest"` wins here without a collision.
#
# This is only safe as a fleet-wide default because gisnix's nixpkgs now
# carries ZFS 2.4.4 — the first OpenZFS release to support the 7.x kernel
# series. A ZFS root on an older ZFS would refuse to build against 7.2.
{ lib, pkgs, ... }:
{
  boot.kernelPackages = lib.mkDefault pkgs.linuxKernel.packages.linux_7_2;
}
