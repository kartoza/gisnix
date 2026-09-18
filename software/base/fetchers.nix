{ pkgs, ... }:
# From https://github.com/XNM1/linux-nixos-hyprland-config-dotfiles/blob/main/nixos/info-fetchers.nix
# And wimpysworld/nix-config/home-manager/default.nix
{
  environment.systemPackages = with pkgs; [
    chafa # Terminal image viewer
    cpufetch # Terminal CPU info
    duf # Modern Unix `df`
    # See home/home-config/console-apps/fastfetch/ for custom fastfetch
    #fastfetch # Modern Unix system info
    neo-cowsay # Terminal ASCII cows
    onefetch # Terminal git project info
    ramfetch # Terminal system info
    writedisk # Modern Unix `dd`
    onefetch # git info
    cpufetch # cpu info
    ramfetch # ram info
    starfetch # star count
    octofetch # github info
    zfxtop # zfs monitor
    # vulkan-tools
    # opencl-info
    # clinfo
    # vdpauinfo
    # libva-utils
    #nvtop # nvidia gpu monitor ## XXX Disabled to avoid pulling in cuda which takes ages to build
    dig # dns lookup
  ];
}
