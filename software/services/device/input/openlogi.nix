# OpenLogi — local-first Logitech HID++ device control (button remap,
# DPI, SmartShift). Fills the gap Solaar used to cover before its removal
# (see piper.nix's header): libratbag/Piper talks to gaming mice over its
# own protocol, not HID++, so the MX-series line had no vendor-tool
# coverage in between.
{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.openlogi ];

  # Grants the active-seat user uaccess to the hidraw/evdev nodes and the
  # uinput node OpenLogi's agent needs — see the rules file itself
  # (shipped in the package) for why two matchers are needed per
  # transport (USB sysfs vs. Bluetooth's virtual uhid bus).
  services.udev.packages = [ pkgs.openlogi ];

  # The packaged systemd unit targets /usr/bin (install.sh's path, not
  # ours); redeclare it pointed at the store path instead. Upstream's own
  # unit carries WantedBy=graphical-session.target, so this mirrors that
  # default rather than leaving it for each user to enable by hand.
  systemd.user.services.openlogi-agent = {
    description = "OpenLogi background agent (Logitech HID++ device control)";
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.openlogi}/bin/openlogi-agent";
      Restart = "on-failure";
      RestartSec = 5;
    };
    wantedBy = [ "graphical-session.target" ];
  };
}
