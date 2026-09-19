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
  geodiff,
  ...
}:

let
  # Deliberately NOT a flake input — see qgis-dev.nix for why. Bump this to
  # track the release-3_44 branch: `git ls-remote
  # https://github.com/qgis/QGIS release-3_44`.
  qgisLatestRev = "411a0f22d90b6ced0097cc069784a5a5054e0b71";
  qgisLatestFlake = builtins.getFlake "github:qgis/QGIS/${qgisLatestRev}";

  wrapQgis = import ../wrap-qgis.nix { inherit pkgs lib; };

  # PCRaster + Whitebox Workflows, built against this QGIS's own python
  qgisPythonExtras = import ../qgis-python-extras.nix;

  qgisLatestGitBase =
    qgisLatestFlake.packages.${pkgs.stdenv.hostPlatform.system}.default
      or qgisLatestFlake.defaultPackage.${pkgs.stdenv.hostPlatform.system};

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
