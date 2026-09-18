{
  inputs,
  pkgs,
  lib,
  geodiff,
  ...
}:

let
  unstablePkgs = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
  };

  # Version in the launcher name so a dock full of QGIS icons is tellable
  # apart. Follows the flake's pinned nixpkgs-unstable automatically.
  appName = "QGIS Latest ${lib.getVersion unstablePkgs.qgis}";

  wrapQgis = import ./wrap-qgis.nix { inherit pkgs lib; };

  # PCRaster + Whitebox Workflows, built against this QGIS's own python
  qgisPythonExtras = import ./qgis-python-extras.nix;

  # Get the geodiff package - for merging maps support
  pygeodiff = geodiff.packages.${pkgs.stdenv.hostPlatform.system}.default;

  qgisLatest = wrapQgis (
    unstablePkgs.qgis.override {
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
          pygeodiff
        ])
        ++ qgisPythonExtras ps;
    }
  );

  # Create a desktop item for QGIS Latest because nix pkgs makes the same item
  # for both QGIS stable and latest
  qgisLatestApp = pkgs.makeDesktopItem {
    name = "qgis-latest";
    desktopName = appName;
    genericName = "Geographic Information System";
    exec = "${qgisLatest}/bin/qgis";
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
    qgisLatest
    qgisLatestApp
  ];
}
