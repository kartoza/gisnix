# Xbox controllers, wired or wireless-with-dongle.
#
# `xpad` is the in-kernel driver and does the work. There used to be an
# `xboxdrv` package here as well — the old userspace driver — but nixpkgs has
# since dropped it, and this module had gone unimported for long enough that
# nobody noticed it would no longer evaluate.
#
# xpad covers the controllers this fleet sees. If a pad turns up that it does
# not handle, the modern answer is xone or xpadneo rather than reviving
# xboxdrv.
{
  config,
  pkgs,
  ...
}:
{
  boot.kernelModules = [ "xpad" ];

  # Let a normal user's applications read the pad without a seat-management
  # detour. MODE 0666 is deliberate: this is a game controller, not a
  # security boundary.
  services.udev.extraRules = ''
    # Xbox controllers
    KERNEL=="event*", SUBSYSTEM=="input", ATTRS{name}=="Microsoft X-Box 360 pad", MODE="0666"
  '';
}
