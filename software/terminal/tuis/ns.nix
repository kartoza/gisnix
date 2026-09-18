{ pkgs, ... }:
{
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "ns" ''
      # Nix Search wrapper using nix-search-tv with fzf preview
      nix-search-tv print | fzf --preview 'nix-search-tv preview {}' --scheme history
    '')
  ];
}
