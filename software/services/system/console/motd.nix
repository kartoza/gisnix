{ pkgs, ... }:

let
  motd = ''
    This is a Kartoza system. Unauthorized access is prohibited.
  '';
in
{
  environment.etc."motd".text = motd;
}
