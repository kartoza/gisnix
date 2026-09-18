{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
  ];
  # See https://nixos.wiki/wiki/Fwupd for more info
  services.fwupd.enable = true;

}
