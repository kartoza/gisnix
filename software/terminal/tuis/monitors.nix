# System monitors.
#
# The full-screen kind: what is using the processor, which kernel modules are
# loaded, how the wireless link is behaving. Moved out of base/utilities.nix
# and base/fetchers.nix, neither of which was about interactive tools.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    btop # processes, memory, disks, network
    kmon # kernel modules
    wavemon # wireless link quality
  ];
}
