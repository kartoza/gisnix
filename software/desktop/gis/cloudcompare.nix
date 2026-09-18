{ pkgs, ... }:

{

  environment.systemPackages = with pkgs; [
    cloudcompare # lidar data workbench - note run CloudCompare (case sensitive) to start it,
  ];
}
