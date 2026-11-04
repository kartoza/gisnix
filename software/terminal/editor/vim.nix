# Vim configuration using timvim neovim distribution
{ pkgs, inputs, ... }:
{
  environment.systemPackages = [
    # Use timvim - complete neovim distribution, built with the nvf framework
    inputs.timvim.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  environment.shellAliases = {
    vim = "nvim";
    vi = "nvim";
    # Plain upstream Neovim, no timvim config — nvf-built distros like
    # timvim bake their config into an explicit `-u` the wrapper passes
    # internally, so they never read ~/.config/nvim; this is nixpkgs'
    # own unwrapped neovim, entirely separate from that wrapper, so it
    # starts with zero config/plugins without needing --clean or -u NONE.
    # Named distinctly (not `nvim`) so both packages can coexist in
    # environment.systemPackages without a bin/nvim collision.
    nvim-vanilla = "${pkgs.neovim}/bin/nvim";
  };

  # EDITOR belongs with the editor. base/fish.nix used to set this, which
  # meant a host taking base without this bundle had $EDITOR pointing at a
  # binary nothing installed — git, crontab and sudoedit all failing on a
  # machine that looked fine. fish's interactiveShellInit is `types.lines`,
  # so this definition merges with the one in base rather than replacing it.
  programs.fish.interactiveShellInit = ''
    set -gx EDITOR nvim
    alias vim nvim
    alias nvim-vanilla "${pkgs.neovim}/bin/nvim"
  '';
}
