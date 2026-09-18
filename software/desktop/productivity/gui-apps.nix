# Desktop productivity applications: documents, notes, money, diagrams.
#
# This file used to be the desktop dumping ground — forty-four packages
# including video editors, a Mastodon client, a 2FA generator and virt-manager.
# It predated the taxonomy and survived it, which is how a "productivity"
# bundle came to own Blender. Everything that belonged elsewhere has moved to
# the bundle named after it; see git history for the split.
#
# Browsers live in ../browsers/browsers.nix.

{ pkgs, ... }:
{
  # Logseq (stable AND unstable nixpkgs alike) still pins electron 39,
  # which is EOL and marked insecure — upstream logseq has been parked on
  # 0.10.x for a long time. Allow exactly that electron for exactly as
  # long as we ship logseq; remove this line together with the package,
  # or when nixpkgs moves logseq to a maintained electron.
  nixpkgs.config.permittedInsecurePackages = [ "electron-39.8.10" ];

  environment.systemPackages = with pkgs; [
    drawio
    gedit
    gnome-calculator
    gnome-decoder # QR code scanner and generator
    gnucash
    libreoffice-fresh
    logseq
    paperwork
    pdfarranger # rotate, join and split PDFs; xournal++ edits them
    xournalpp
    libsForQt5.qt5.qttools # qtdesigner, assistant — for QGIS plugin work
  ];
}
