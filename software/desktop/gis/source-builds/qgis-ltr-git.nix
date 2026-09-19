##
## NixOS module to install the ltr QGIS from source from Git
##

##
## For hints on how to set up python deps with QGIS
## see the top level README.md in this repo
##
{
  pkgs,
  lib,
  geodiff,
  ...
}:

let
  # Deliberately NOT a flake input — see qgis-dev.nix for why. Bump this to
  # track the release-3_40 branch: `git ls-remote
  # https://github.com/qgis/QGIS release-3_40`.
  qgisLtrRev = "4178dfd8b91ceb044235ef6181d272d6ff1e30c6";
  qgisLtrFlake = builtins.getFlake "github:qgis/QGIS/${qgisLtrRev}";

  wrapQgis = import ../wrap-qgis.nix { inherit pkgs lib; };

  # PCRaster + Whitebox Workflows, built against this QGIS's own python
  qgisPythonExtras = import ../qgis-python-extras.nix;

  qgisLtrGitBase =
    qgisLtrFlake.packages.${pkgs.stdenv.hostPlatform.system}.default
      or qgisLtrFlake.defaultPackage.${pkgs.stdenv.hostPlatform.system};

  # Version in the launcher name so a dock full of QGIS icons is tellable apart.
  appName =
    "QGIS LTR (Git)"
    + lib.optionalString (lib.getVersion qgisLtrGitBase != "") " ${lib.getVersion qgisLtrGitBase}";

  # Get the geodiff package
  pygeodiff = geodiff.packages.${pkgs.stdenv.hostPlatform.system}.default;

  qgisLtrGit = wrapQgis (
    qgisLtrGitBase.override {
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

  qgisLtrAppGit = pkgs.makeDesktopItem {
    name = "qgis-ltr";
    desktopName = appName;
    genericName = "Geographic Information System";
    exec = "${qgisLtrGit}/bin/qgis";
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
    qgisLtrGit
    qgisLtrAppGit
  ];
}
