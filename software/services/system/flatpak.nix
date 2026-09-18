{
  config,
  pkgs,
  ...
}:
{
  ### Flatpack support
  ### see https://flatpak.org/setup/NixOS
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "*";
  };
  services.flatpak.enable = true;
}
