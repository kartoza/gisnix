##
## For hints on how to set up python deps with QGIS
## see the top level README.md in this repo
##
{
  pkgs,
  lib,
  config,
  qgis-master-repo,
  geodiff,
  ...
}:

let
  wrapQgis = import ../wrap-qgis.nix { inherit pkgs lib; };

  # PCRaster + Whitebox Workflows, built against this QGIS's own python
  qgisPythonExtras = import ../qgis-python-extras.nix;

  # Access the flake input directly - this is the most common pattern
  qgisDevBase =
    qgis-master-repo.packages.${pkgs.stdenv.hostPlatform.system}.default
      or qgis-master-repo.defaultPackage.${pkgs.stdenv.hostPlatform.system};

  # Version in the launcher name so a dock full of QGIS icons is tellable
  # apart (master builds may carry no version; then the name stays plain).
  appName =
    "QGIS Dev" + lib.optionalString (lib.getVersion qgisDevBase != "") " ${lib.getVersion qgisDevBase}";

  # Get the geodiff package
  pygeodiff = geodiff.packages.${pkgs.stdenv.hostPlatform.system}.default;

  qgisDev = wrapQgis (
    qgisDevBase.override {
      extraPythonPackages =
        ps:
        (with ps; [
          numpy
          requests
          #debugpy
          # future # Removed: not compatible with Python 3.13
          matplotlib
          pandas
          geopandas
          plotly
          #pyqt5_with_qtwebkit
          pyqtgraph
          rasterio
          sqlalchemy
          pyqtwebengine
          pygeodiff
        ])
        ++ qgisPythonExtras ps;
    }
  );

  qgisDevApp = pkgs.makeDesktopItem {
    name = "qgis-dev";
    desktopName = appName;
    genericName = "Geographic Information System";
    exec = "${qgisDev}/bin/qgis";
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
  imports = [ ../qgis-wayland-appid.nix ];

  environment.systemPackages = with pkgs; [
    qgisDev
    qgisDevApp
  ];
}
