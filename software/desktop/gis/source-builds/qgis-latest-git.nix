##
## NixOS module to install the latest QGIS from source from Git
##

##
## For hints on how to set up python deps with QGIS
## see the top level README.md in this repo
##
{
  pkgs,
  lib,
  qgis-latest-repo,
  geodiff,
  ...
}:

let
  wrapQgis = import ../wrap-qgis.nix { inherit pkgs lib; };

  # PCRaster + Whitebox Workflows, built against this QGIS's own python
  qgisPythonExtras = import ../qgis-python-extras.nix;

  # Access the flake input directly - this is the most common pattern
  qgisLatestGitBase =
    qgis-latest-repo.packages.${pkgs.stdenv.hostPlatform.system}.default
      or qgis-latest-repo.defaultPackage.${pkgs.stdenv.hostPlatform.system};

  # Version in the launcher name so a dock full of QGIS icons is tellable apart.
  appName =
    "QGIS Latest (Git)"
    + lib.optionalString (
      lib.getVersion qgisLatestGitBase != ""
    ) " ${lib.getVersion qgisLatestGitBase}";

  # Get the geodiff package
  pygeodiff = geodiff.packages.${pkgs.stdenv.hostPlatform.system}.default;

  qgisLatestGit = wrapQgis (
    qgisLatestGitBase.override {
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
          pyqtwebengine
          pygeodiff
        ])
        ++ qgisPythonExtras ps;
    }
  );

  qgisLatestAppGit = pkgs.makeDesktopItem {
    name = "qgis-latest";
    desktopName = appName;
    genericName = "Geographic Information System";
    exec = "${qgisLatestGit}/bin/qgis";
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
    qgisLatestGit
    qgisLatestAppGit
  ];
}
