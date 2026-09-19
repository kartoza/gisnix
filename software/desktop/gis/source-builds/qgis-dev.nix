##
## For hints on how to set up python deps with QGIS
## see the top level README.md in this repo
##
{
  pkgs,
  lib,
  config,
  geodiff,
  ...
}:

let
  # Deliberately NOT a flake input: every input in flake.nix's `inputs =
  # {...}` block gets fetched (and, for a flake input like QGIS's own repo,
  # its own sub-inputs recursively resolved) on ANY flake evaluation —
  # including a bare `nix develop` that never touches this opt-in,
  # hours-of-build-time bundle. `builtins.getFlake` on a fully pinned rev
  # is lazy: it only fetches when THIS expression is actually evaluated,
  # which only happens for a host that enables desktop-gis-source-builds.
  #
  # Bump this to track new QGIS master progress: find the current commit
  # with `git ls-remote https://github.com/qgis/QGIS master`.
  qgisMasterRev = "09d73a2b827841320e798d1f18c84a4776dbd265";
  qgisMasterFlake = builtins.getFlake "github:qgis/QGIS/${qgisMasterRev}";

  wrapQgis = import ../wrap-qgis.nix { inherit pkgs lib; };

  # PCRaster + Whitebox Workflows, built against this QGIS's own python
  qgisPythonExtras = import ../qgis-python-extras.nix;

  qgisDevBase =
    qgisMasterFlake.packages.${pkgs.stdenv.hostPlatform.system}.default
      or qgisMasterFlake.defaultPackage.${pkgs.stdenv.hostPlatform.system};

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
