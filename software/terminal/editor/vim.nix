# Vim configuration using timvim neovim distribution
{ pkgs, inputs, ... }:
{
  environment.systemPackages = [
    # Use timvim - complete neovim distribution with nvf
    inputs.nvf.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  environment.shellAliases = {
    vim = "nvim";
    vi = "nvim";
  };

  # EDITOR belongs with the editor. base/fish.nix used to set this, which
  # meant a host taking base without this bundle had $EDITOR pointing at a
  # binary nothing installed — git, crontab and sudoedit all failing on a
  # machine that looked fine. fish's interactiveShellInit is `types.lines`,
  # so this definition merges with the one in base rather than replacing it.
  programs.fish.interactiveShellInit = ''
    set -gx EDITOR nvim
    alias vim nvim
  '';
}
