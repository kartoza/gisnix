# Gaming-mouse configuration: DPI, polling rate, button mapping, LEDs.
#
# Two halves that are easy to confuse:
#
#   ratbagd  the system daemon that actually talks to the mouse. Without it
#            running, Piper opens and reports no devices — which looks like
#            an unsupported mouse rather than a missing service.
#   piper    the GTK front-end. It is only a client of ratbagd and does
#            nothing on its own.
#
# So both are needed, and the daemon is the part that matters.
#
# This covers Logitech G-series, Steelseries, Roccat and others through
# libratbag. Razer devices go through openrazer.nix instead; the two claim
# different hardware and coexist.
#
# Solaar used to sit alongside this for Logitech HID++ devices and was
# removed; openlogi.nix now fills that role (DPI, SmartShift, and button
# remap — including the MX Vertical's silver-button-as-Super mapping —
# for HID++ mice and keyboards). libratbag itself still does NOT do key
# diversion, which is why that gap needed a separate tool rather than an
# addition to this one.
{ pkgs, ... }:
{
  # The daemon. Ships its own udev rules, so a normal user can write to the
  # mouse without a polkit detour.
  services.ratbagd.enable = true;

  environment.systemPackages = with pkgs; [
    piper # GUI front-end for ratbagd
  ];
}
