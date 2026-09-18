{
  config,
  pkgs,
  inputs,
  ...
}:
# Temporarily disabled due to missing nixpkgs-master input
# let
#   unstablePkgs = inputs.nixpkgs-master.legacyPackages.${pkgs.system};
# in
{
  # Install available any packages from unstable channel here
  # Use regular pkgs as fallback
  environment.systemPackages = with pkgs; [
    gradia # screenshot annotation tool (from regular channel as fallback)
    kdePackages.kdenlive # video editor (moved out of top-level into kdePackages)
  ];

}
