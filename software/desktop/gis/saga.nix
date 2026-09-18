{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    saga
  ];
}
