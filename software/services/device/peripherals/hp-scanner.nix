{ pkgs, ... }:

{
  # `hplipWithPlugin` carries HP's binary plugin and is unfree, while plain
  # `hplip` is not — and `lib.getName` reports both as "hplip", which is the
  # string the allow-list in services/system/unfree.nix matches on. Without
  # this declaration the module cannot be enabled on any host at all:
  # evaluation stops at "Refusing to evaluate package 'hplip'".
  # printing.nix uses the free `hplip`, which is why the gap went unnoticed
  # for so long — that bundle works, this one never did.
  kartoza.unfreePackages = [ "hplip" ];

  # see https://discourse.nixos.org/t/scanning-with-hp-scanner/23415
  hardware.sane = {
    enable = true;
    extraBackends = [ pkgs.hplipWithPlugin ];
  };

  # To enable network-discovery
  # see config/avahi.nix

  # Add system wide packages
  environment.systemPackages = with pkgs; [
    simple-scan # GNOME document scanner GUI for the SANE backends above
  ];
}
