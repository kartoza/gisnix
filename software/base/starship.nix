{ pkgs, ... }:
{
  # Initialise starship per-shell in each shell's own init, so neither
  # shell runs the other's snippet. The previous combined
  # environment.interactiveShellInit ran the fish line inside bash too
  # ("starship init fish | source"), which errored with "source: filename
  # argument required" and smeared the bash prompt. Fish's init lives in
  # software/base/fish.nix.
  programs.bash.interactiveShellInit = ''
    eval "$(starship init bash)"
  '';

  environment.etc."starship.toml" = {
    mode = "0555";
    source = ../../dotfiles/starship.toml;
  };

  environment.etc."starship-qgis.toml" = {
    mode = "0555";
    source = ../../dotfiles/starship-qgis.toml;
  };

  environment.variables = {
    STARSHIP_CONFIG = "/etc/starship.toml";
  };

  environment.systemPackages = with pkgs; [
    starship
  ];
}
