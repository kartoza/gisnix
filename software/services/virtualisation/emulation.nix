# Cross-architecture emulation support
# Enables building aarch64 packages/ISOs on x86_64 systems via QEMU binfmt
{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Enable binfmt emulation for aarch64
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # Add aarch64-linux to extra platforms so nix can build for it
  nix.settings.extra-platforms = [ "aarch64-linux" ];
}
