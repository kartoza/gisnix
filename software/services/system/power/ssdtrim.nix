{ config, pkgs, ... }:
{
  # see https://www.techtarget.com/searchstorage/definition/TRIM
  services.fstrim.enable = true;
}
