{ pkgs, ... }:
{
  # Note you need at least version e383ef732ef9781c5db185d3583029f802747a9a of Nixpkgs to use this
  # see https://github.com/NixOS/nixpkgs/issues/315201
  # and https://github.com/NixOS/nixpkgs/pull/316907
  environment.systemPackages = with pkgs; [
    whitebox-tools
  ];
}
