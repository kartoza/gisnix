{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.openrazerSupport;
in
{
  options.services.openrazerSupport.users = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Users granted access to Razer hardware (RGB, DPI, battery).";
    example = [ "alice" ];
  };

  config = {
    # Razer peripheral support (RGB, DPI, battery) — kernel driver + daemon.
    # Polychromatic is the GUI: effects, per-key lighting, profiles.
    hardware.openrazer = {
      enable = true;
      users = cfg.users;
    };

    environment.systemPackages = [ pkgs.polychromatic ];
  };
}
