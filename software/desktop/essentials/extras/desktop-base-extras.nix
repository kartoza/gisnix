# Desktop applications beyond the minimum a COSMIC session needs.
#
# Split out of desktop-base.nix, where these sat behind a `slimDesktop`
# boolean that has since been removed. They are a separate module rather than
# a longer list because the distinction is real — the minimum for a usable
# session, versus what a workstation also wants — and a separate module can be
# left out by a host that does not want it, which a boolean tested in thirteen
# files could not usefully express.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    copyq # clipboard history, with image support
    evince # PDF viewer
    loupe # image viewer: fast, and reads most formats
    sushi # quick-look preview in Nautilus (spacebar)
    papers # GNOME document viewer
    # Wayland screen recorder. Also referenced (by store path) by the
    # record-gif keybind glue in the cosmic module, same as grim/slurp/satty
    # above: it speaks ext-image-copy-capture-v1, which is the capture
    # protocol cosmic-comp actually implements.
    wl-screenrec
    # Region-to-GIF recorder. NOTE: broken under cosmic-comp — it drives
    # wf-recorder, which only speaks zwlr_screencopy_unstable_v1 and dies
    # with "compositor doesn't support wlr-screencopy-unstable-v1". Kept
    # only because its portal backend still works if you accept the portal's
    # picker; record-gif no longer uses it. See cosmic/packages.nix.
    wlgif
    gnome-disk-utility # Disk management
    pavucontrol # Volume control (COSMIC has its own audio applet)
    networkmanagerapplet # Network GUI (COSMIC has its own network applet)
  ];
}
