{ config, pkgs, ... }:
{

  # This is my own ZFS backup tool
  # See https://github.com/timlinux/zfs-backup
  environment.systemPackages = with pkgs; [
    zfs-backup
  ];

}
