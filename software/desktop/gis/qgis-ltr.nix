{
  pkgs,
  lib,
  geodiff,
  ...
}:

let
  # LTR comes from the *stable* channel (the flake's nixpkgs input), not
  # unstable: stable only takes QGIS point releases as backports after they
  # build, so it cannot be broken by trunk churn (as the 2026-09 sip bump
  # broke qgis-ltr on unstable). LTR-on-stable and Latest-on-unstable is
  # also the natural pairing — the conservative channel carries the
  # conservative QGIS.

  # Version in the launcher name so a dock full of QGIS icons is tellable
  # apart. Follows the flake's stable nixpkgs pin automatically.
  appName = "QGIS LTR ${lib.getVersion pkgs.qgis-ltr}";

  wrapQgis = import ./wrap-qgis.nix { inherit pkgs lib; };

  # PCRaster + Whitebox Workflows, built against this QGIS's own python
  qgisPythonExtras = import ./qgis-python-extras.nix;

  # Get the geodiff package - for merging maps support
  pygeodiff = geodiff.packages.${pkgs.stdenv.hostPlatform.system}.default;

  qgisLtr = wrapQgis (
    pkgs.qgis-ltr.override {
      extraPythonPackages =
        ps:
        (with ps; [
          numpy
          requests
          matplotlib
          pandas
          geopandas
          plotly
          pyqtgraph
          rasterio
          sqlalchemy
          #pyqtwebengine
          pygeodiff
        ])
        ++ qgisPythonExtras ps;
    }
  );

  # Create a desktop item for QGIS Ltr because nix pkgs makes the same item
  # for both QGIS stable and ltr
  qgisLtrApp = pkgs.makeDesktopItem {
    name = "qgis-ltr";
    desktopName = appName;
    genericName = "Geographic Information System";
    exec = "${qgisLtr}/bin/qgis";
    icon = "qgis";
    categories = [
      "Science"
      "Geography"
    ];
    comment = "A Geographic Information System";
    startupWMClass = "qgis";
  };
in
{
  imports = [ ./qgis-wayland-appid.nix ];

  environment.systemPackages = [
    qgisLtr
    qgisLtrApp
  ];
}
