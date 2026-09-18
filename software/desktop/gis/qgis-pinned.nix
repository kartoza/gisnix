## Shared builder for the pinned historical QGIS versions.
##
## Each entry in qgis-versions.json pins one QGIS minor series to the last
## nixpkgs *channel* commit that shipped it — channel commits are built by
## Hydra, so the binaries come straight from cache.nixos.org. The sha256 of
## each nixpkgs tarball is cached in the manifest, making evaluation a
## zero-cost operation for everyone after the person who computed it.
##
## Nothing here evaluates unless the corresponding version bundle is
## enabled in `kz configure`, so disabled versions cost nothing at all.
##
## 3.x/4.x entries (extras = true) take the standard python packages from
## their own pinned nixpkgs — pure binary-cache hits, no source builds.
## Packages that do not exist in an old package set are simply skipped.
## 1.8/2.x predate the extraPythonPackages interface and install plain.
##
## The per-series modules under versions/ are generated from the manifest
## by utils/gen-qgis-versions.py — edit the manifest, not the modules.
series:
{ pkgs, lib, ... }:
let
  manifest = builtins.fromJSON (builtins.readFile ./qgis-versions.json);
  entry = manifest.${series};
  slug = lib.replaceStrings [ "." ] [ "-" ] series;

  pinnedPkgs =
    import
      (fetchTarball {
        url = "https://github.com/NixOS/nixpkgs/archive/${entry.rev}.tar.gz";
        sha256 = entry.sha256;
      })
      {
        system = pkgs.stdenv.hostPlatform.system;
        # A frozen snapshot ships its era's Qt/WebKit/Python, some of which its
        # own nixpkgs already marked insecure (e.g. qtwebkit under QGIS 3.x).
        # Allowing them inside this isolated import is the point of a
        # historical pin — the host's real nixpkgs config is unaffected, and
        # the version bundle descriptions carry the vintage warning.
        config.allowInsecurePredicate = _: true;
      };

  base = pinnedPkgs.${entry.attr};

  # The standard QGIS python companions, taken from the *pinned* package
  # set so ABI and python version always match — filtered to what that
  # era of nixpkgs actually had, and to what still evaluates there: a
  # package whose dependency the snapshot itself marks broken (e.g.
  # geopandas -> descartes in the python3.8 era) is skipped just like one
  # that never existed. Hydra never built broken-marked packages, so
  # allowBroken would only trade this eval error for an uncached source
  # build of something known-broken.
  pythonExtras =
    ps:
    let
      usable =
        name: builtins.hasAttr name ps && (builtins.tryEval (builtins.seq ps.${name}.drvPath true)).success;
    in
    map (name: ps.${name}) (
      builtins.filter usable [
        "numpy"
        "requests"
        "matplotlib"
        "pandas"
        "geopandas"
        "plotly"
        "pyqtgraph"
        "rasterio"
        "sqlalchemy"
      ]
    );

  qgisPinned = if entry.extras then base.override { extraPythonPackages = pythonExtras; } else base;

  appName = "QGIS ${entry.version}";
  qgisPinnedApp = pkgs.makeDesktopItem {
    name = "qgis-${slug}";
    desktopName = appName;
    genericName = "Geographic Information System";
    exec = "${qgisPinned}/bin/qgis";
    icon = "qgis";
    categories = [
      "Science"
      "Geography"
    ];
    comment = "A Geographic Information System (pinned ${entry.version})";
    startupWMClass = "qgis";
  };
in
{
  imports = [ ./qgis-wayland-appid.nix ];

  environment.systemPackages = [
    qgisPinned
    qgisPinnedApp
  ];
}
