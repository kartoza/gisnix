# Stop charging the battery short of full.
#
# Holding a lithium cell at 100% ages it faster than stopping around 80%, so a
# machine that lives on mains most of the time is worth limiting. A machine
# that actually needs its full capacity is not.
#
# WHY THIS REPLACED TLP
#
# The only thing TLP was ever configured to do in this flake was set these
# thresholds — and it never did, because `services.tlp.settings` is inert
# without `services.tlp.enable`, which nothing set. The thresholds sat in
# software/services/system/power/tlp.nix looking applied, on seven hosts, for
# as long as the file existed.
#
# Enabling TLP instead was the other option and a worse one here: the fleet
# runs COSMIC, whose power menu is driven by power-profiles-daemon, and the
# two write the same sysfs knobs and undo each other. A desktop slider that
# lies about the machine is worse than no slider.
#
# So: the same intent, through the one file the kernel actually reads, with no
# daemon involved.
#
# NOT EVERY MACHINE WANTS ONE
#
# Default is null — no limit, which is what every host has effectively had.
# island and mainland must NOT have one: their RTX 4060 and APU together can
# outdraw the charger, and a machine that may not charge above 80% can end up
# discharging while plugged in.
#
# Frameworks are a separate case again. On Ryzen AI 300 the sysfs threshold
# does not persist, so abyss sets its limit at the embedded controller with
# `ectool fwchargelimit` in hosts/abyss/hardware.nix. Setting both would be
# two mechanisms disagreeing.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.kartoza.power;
in
{
  options.kartoza.power.chargeLimit = lib.mkOption {
    type = lib.types.nullOr (lib.types.ints.between 50 100);
    default = null;
    example = 80;
    description = ''
      Percentage at which to stop charging, or null for no limit.

      Written to `charge_control_end_threshold` on every battery that exposes
      it. Laptops that do not expose it are unaffected and report so in the
      journal rather than failing.
    '';
  };

  config = lib.mkIf (cfg.chargeLimit != null) {
    systemd.services.kartoza-charge-limit = {
      description = "Stop charging the battery at ${toString cfg.chargeLimit}%";
      wantedBy = [ "multi-user.target" ];
      # The threshold is reset by a firmware update, a battery swap, and on
      # some hardware by a suspend cycle, so it is reapplied on resume rather
      # than only at boot.
      after = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -u
        found=0
        for battery in /sys/class/power_supply/*; do
          threshold="$battery/charge_control_end_threshold"
          [ -w "$threshold" ] || continue
          echo ${toString cfg.chargeLimit} > "$threshold"
          echo "charge limit ${toString cfg.chargeLimit}% set on $(basename "$battery")"
          found=1
        done
        if [ "$found" = 0 ]; then
          echo "no battery exposes charge_control_end_threshold; nothing to set" >&2
        fi
      '';
    };

    powerManagement.resumeCommands = ''
      ${pkgs.systemd}/bin/systemctl restart kartoza-charge-limit.service || true
    '';
  };
}
