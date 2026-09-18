## Wrap a QGIS derivation so that bundled-plugin native libraries
## (e.g. the Mergin plugin's prebuilt libpygeodiff .so) can resolve
## their NEEDED libraries via LD_LIBRARY_PATH.
##
## Usage:
##   let wrapQgis = import ./wrap-qgis.nix { inherit pkgs lib; };
##   in wrapQgis qgisDerivation
{ pkgs, lib }:
qgis:
pkgs.symlinkJoin {
  name = "${qgis.pname or qgis.name or "qgis"}-wrapped";
  paths = [ qgis ];
  buildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/qgis \
      --prefix XDG_DATA_DIRS : "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}" \
      --prefix XDG_DATA_DIRS : "${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}" \
      --prefix GIO_EXTRA_MODULES : "${pkgs.glib-networking}/lib/gio/modules" \
      --prefix LD_LIBRARY_PATH : "${
        lib.makeLibraryPath [
          pkgs.sqlite
          pkgs.openssl
          pkgs.zlib
          pkgs.expat
          pkgs.libffi
          pkgs.stdenv.cc.cc.lib
          pkgs.geos
          pkgs.proj
          pkgs.gdal
          pkgs.libspatialite
        ]
      }"
  '';
}
