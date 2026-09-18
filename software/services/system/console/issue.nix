{ pkgs, ... }:

let
  issue = ''
    This is a Kartoza system. Unauthorized access is prohibited.
  '';
in
{
  environment.etc."issue".text = issue;
  environment.etc."issue.net".text = issue;
}
