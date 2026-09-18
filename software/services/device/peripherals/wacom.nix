# Wacom graphics tablet support.
#
# NixOS's own documentation is thin here; the Arch wiki is better:
# https://wiki.archlinux.org/title/Graphics_tablet
#
# `wacomtablet` used to be in this list. It was the KDE configuration GUI —
# the previous comment here called it "loads a lot of kde crap too" — and
# nixpkgs has since moved it under kdePackages. This fleet removed KDE
# entirely, so it is dropped rather than repointed: the driver and the
# xsetwacom CLI are what actually make the tablet work.
#
# This module had gone unimported for long enough that the missing package
# went unnoticed until the bundle work adopted it.
{ pkgs, ... }:
{
  # The pad buttons on an Intuos, mapped to what they are useful for while
  # drawing. Devices are addressed by number rather than name: addressing by
  # name did not work reliably. `xsetwacom list --devices` gives the numbers.
  environment.interactiveShellInit = ''
    # 25 = pad on Intuos
    xsetwacom set 25 Button 1 "key +ctrl z -ctrl"
    # simplify geometry in inkscape
    xsetwacom set 25 Button 2 "key +ctrl l -ctrl"
  '';

  # Some models also need pairing over Bluetooth before this takes effect.
  services.xserver.wacom.enable = true;

  environment.systemPackages = with pkgs; [
    xf86_input_wacom # the X/libinput driver
    libwacom # device database
  ];
}
