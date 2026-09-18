{ config, pkgs, ... }:

{

  # Enable CUPS to print documents.
  services.printing.enable = true;
  services.printing.startWhenNeeded = true;
  services.printing.drivers = with pkgs; [
    gutenprint
    hplip
  ];
  environment.systemPackages = with pkgs; [
    hplip
  ];
}
