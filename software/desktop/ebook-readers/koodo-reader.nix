# Koodo Reader — cross-platform e-book reader with library management.
#
# This was a hand-rolled AppImage wrapper: a package derivation taking
# { appimageTools, fetchurl } that had been filed as a NixOS module. The
# module system passes `outputs`, which its argument list rejected, so it
# could never be imported — which is why nothing imported it, and why the
# breakage went unnoticed until the bundle work adopted it.
#
# nixpkgs packages it, so none of that is needed.
{ pkgs, ... }:
{
  # Koodo Reader pins electron 41, which is EOL and marked insecure —
  # same situation gui-apps.nix already carries for Logseq's electron 39.
  # kartoza.insecurePackages (services/system/unfree.nix), not
  # nixpkgs.config.permittedInsecurePackages directly — the latter is a
  # bare attrs key with no list-merging, so gui-apps.nix's own permit and
  # this one would collide and only one would survive (confirmed the hard
  # way: this exact package refused to evaluate with the direct
  # assignment in place, on a host taking both bundles). Remove this line
  # together with the package, or when nixpkgs moves koodo-reader to a
  # maintained electron.
  kartoza.insecurePackages = [ "electron-41.9.1" ];

  environment.systemPackages = [ pkgs.koodo-reader ];

  # Koodo Reader's own .desktop file claims application/pdf (ebook readers
  # commonly do — PDF is a common e-book format), which silently became the
  # default PDF handler on any host also taking desktop-base-extras
  # (Evince) the moment both desktop files exist together — nothing sets
  # an explicit default otherwise, so whichever app the desktop
  # environment happens to prefer wins. Evince is the one meant to open
  # PDFs by default here; Koodo Reader is for actual ebooks
  # (epub/mobi/etc — see its own MimeType list for the rest).
  environment.etc."xdg/mimeapps.list".text = ''
    [Default Applications]
    application/pdf=org.gnome.Evince.desktop
  '';
}
