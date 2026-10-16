{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    rustgis
  ];
}
