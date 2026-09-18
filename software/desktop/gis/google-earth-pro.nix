{
  pkgs,
  config,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    googleearth-pro
  ];
}
