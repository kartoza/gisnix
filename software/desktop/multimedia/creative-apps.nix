# Creative applications: audio, image, video and 3D authoring.
#
# Moved here from ../productivity/gui-apps.nix, which had accumulated them
# before the taxonomy existed. A host that wants a word processor without
# Blender can now say so.
#
# obs-studio is deliberately absent: ./obs.nix installs it wrapped with its
# plugin set. Both were previously installed at once, and since both provide
# `bin/obs` one silently shadowed the other — which is a good way to lose a
# plugin set without ever being told.

{ pkgs, pkgs-unstable, ... }:
{
  environment.systemPackages = with pkgs; [
    # Audacity rides nixpkgs-unstable, not the pinned release: the 4.x
    # series landed there first (nixos-26.05 still ships 3.7). Fold back
    # to plain `audacity` when the pinned nixpkgs catches up.
    pkgs-unstable.audacity
    blender
    gimp3-with-plugins
    inkscape-with-extensions
    mpv
    qpwgraph # patch bay / audio wiring for pipewire
    shotcut # video editor without the KDE dependencies
    synfigstudio
  ];
}
