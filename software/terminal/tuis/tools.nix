# Full-screen tools that are not an editor, a file manager or a monitor.
#
# gh-dash reviews pull requests, posting composes HTTP requests, television
# is a fuzzy launcher over arbitrary sources. All three take over the
# terminal, which is what puts them here rather than in base.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    gh-dash # GitHub pull requests and issues
    posting # HTTP client
    television # fuzzy finder over channels
  ];
}
