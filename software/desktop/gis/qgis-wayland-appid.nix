##
## Shared desktop entry so Wayland panels (COSMIC) match QGIS windows
## to a proper icon.
##
## QGIS sets its Wayland app_id to the literal string "org.qgis."
## (the app-name suffix it templates onto "org.qgis." is empty in our
## builds — confirmed with lswt). Panels match running windows to
## desktop entries by app_id, and none of our per-variant entries
## (qgis-ltr, qgis-dev, ...) carry that name, so QGIS windows got a
## generic icon. All Qt QGIS variants share the one app_id, so a single
## entry named after it fixes them all. It must NOT be NoDisplay=true:
## COSMIC skips hidden entries when matching windows, so the entry is
## visible in the launcher alongside the per-variant ones (labelled
## plain "QGIS"). StartupWMClass=qgis additionally covers the Qt4-era
## QGIS 2.18 running via XWayland (WM_CLASS "qgis").
##
## Imported by each qgis-*.nix variant module; the module system
## dedupes repeated imports of the same path.
{ pkgs, ... }:
let
  qgisWaylandMatch = pkgs.runCommand "qgis-wayland-appid-desktop" { } ''
    mkdir -p $out/share/applications
    cat > "$out/share/applications/org.qgis..desktop" << 'DESKTOP'
    [Desktop Entry]
    Type=Application
    Name=QGIS
    GenericName=Geographic Information System
    Exec=qgis
    Icon=qgis
    Terminal=false
    Categories=Science;Geography;
    StartupWMClass=qgis
    DESKTOP
  '';
in
{
  environment.systemPackages = [ qgisWaylandMatch ];
}
