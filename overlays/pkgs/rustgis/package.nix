# rustgis (https://rustgis.app) — GIS desktop app written entirely in
# Rust (egui/eframe), not in nixpkgs. Apache-2.0 — no license-approval
# needed, unlike siggy/perch next to this in the same directory.
#
# ARCHITECTURE: a plain Cargo workspace, crates.io dependencies only (no
# git deps — checked Cargo.lock directly — so no outputHashes block like
# siggy's package.nix carries). eframe/egui for the GUI, wgpu for
# rendering, winit's wayland AND x11 backends both compiled in (see
# apps/rustgis/Cargo.toml's eframe features). GDAL support is an
# OPTIONAL RUNTIME dlopen — rustgis_data::source::gdal::available()
# probes whether libgdal is already on the system at startup (confirmed
# against crates/map/src/source.rs and crates/engine/src/tests.rs) — not
# a build dependency, so GDAL is not a buildInput below.
#
# RUNTIME LIBRARIES ARE ALL DLOPEN'D, NOT LINKED: upstream's own Linux
# packaging script (packaging/package.sh) says so explicitly — "The
# windowing and GPU libraries are loaded at run time" — and its AUR
# PKGBUILD (packaging/aur/render.sh) lists wayland, libx11, libxcursor,
# libxi, libxrandr, libxkbcommon-x11, vulkan-icd-loader and libglvnd as
# optdepends, not depends. A patchelf'd RPATH only reaches DT_NEEDED
# entries, so postFixup below wraps LD_LIBRARY_PATH instead — that's the
# one that actually lets dlopen find them.
#
# crates/render's build.rs downloads 5 Natural Earth GeoJSON files
# (opengeos/rustgis-assets, via assets.rustgis.app) at BUILD time — a
# real build caught this (`error: failed to run custom build command for
# rustgis-render`; the Nix build sandbox has no network at all), so this
# isn't a guess like the rest of this file was before that first build.
# build.rs itself supports exactly this case: set RUSTGIS_DATA_DIR to a
# folder already holding the files and it copies from there instead of
# fetching. The five fetchurl calls below exist for that, and preBuild
# assembles them into one directory.
#
# BUILD-VERIFIED up to this fix, NOT further: the fetchurl hashes were
# computed the same way the source hash below was (downloaded directly,
# hashed with `nix hash file` — no working nix daemon here to build
# with), so the actual compile past this point is still unconfirmed.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  fetchurl,
  pkg-config,
  makeWrapper,
  libxkbcommon,
  wayland,
  vulkan-loader,
  libGL,
  libx11,
  libxcursor,
  libxi,
  libxrandr,
  fontconfig,
  freetype,
}:
let
  runtimeLibs = [
    libxkbcommon
    wayland
    vulkan-loader
    libGL
    libx11
    libxcursor
    libxi
    libxrandr
    fontconfig
    freetype
  ];

  # Natural Earth sample data crates/render's build.rs embeds for the
  # basemap outline and World Atlas sample — see the header comment for
  # why these are fetched here rather than left to build.rs itself.
  rustgisAssets = {
    "countries.geojson" = fetchurl {
      url = "https://assets.rustgis.app/data/countries.geojson";
      hash = "sha256-vvjuYeRmhQSdR7V3uG+3bp9nr0Gj1MOKy2fwAhvzGzY=";
    };
    "countries_chn.geojson" = fetchurl {
      url = "https://assets.rustgis.app/data/countries_chn.geojson";
      hash = "sha256-UkjtPJlmejSKjxT4bCclCNGEc/4YjYrDpOeA7JE/wuo=";
    };
    "cities.geojson" = fetchurl {
      url = "https://assets.rustgis.app/data/cities.geojson";
      hash = "sha256-KMh4RXmXQbGYEio+mrKxoUoVBOt0GHqvHbDTr4p1ix4=";
    };
    "rivers.geojson" = fetchurl {
      url = "https://assets.rustgis.app/data/rivers.geojson";
      hash = "sha256-iXER9LPyvdyYx4mTuEjRrRjOuQu7PsnXA4iMkO33DnM=";
    };
    "lakes.geojson" = fetchurl {
      url = "https://assets.rustgis.app/data/lakes.geojson";
      hash = "sha256-EfSasfcaP/lfrgf4HJBR22wNiOUevWZeKMEMLxG43SQ=";
    };
  };
in
rustPlatform.buildRustPackage rec {
  pname = "rustgis";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "opengeos";
    repo = "RustGIS";
    rev = "v${version}";
    # Computed the same way siggy/package.nix's source hash was: no
    # working nix daemon here, so downloaded the GitHub archive tarball
    # fetchFromGitHub would fetch and hashed the extracted tree with
    # `nix hash path`.
    hash = "sha256-tEIXIZifxrbhcxsH+zMWJ6n3ZOVG6ucVf9KuRMEfPgs=";
  };

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
  };

  # Only the two apps that ship — not xtask (this repo's own build
  # tooling), and not the whole default-members set a plain `cargo build
  # --release` would pull in. Matches upstream's own build command
  # exactly (packaging/package.sh: `cargo build --release --locked -p
  # rustgis -p rustgis-cli`).
  cargoBuildFlags = [
    "-p"
    "rustgis"
    "-p"
    "rustgis-cli"
  ];

  # egui_kittest (a UI snapshot-testing dependency) needs a display to
  # run its tests against — not confirmed to work headless inside a Nix
  # sandbox build (no X11/Wayland, no network for any fixture it might
  # fetch). Disabling rather than risking every host's build hanging or
  # failing on something environmental rather than a real regression.
  doCheck = false;

  # See rustgisAssets above and the header comment: crates/render's own
  # build.rs reads RUSTGIS_DATA_DIR instead of fetching when it's set,
  # copying each file out and checking it looks like GeoJSON (starts
  # with `{`) — real files, not placeholders, so that check passes.
  preBuild = ''
    mkdir -p rustgis-data
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: path: "ln -s ${path} rustgis-data/${name}") rustgisAssets
    )}
    export RUSTGIS_DATA_DIR="$PWD/rustgis-data"
  '';

  nativeBuildInputs = [
    pkg-config
    makeWrapper
  ];

  buildInputs = runtimeLibs;

  # Neither binary's icon/desktop/MIME registration is built by cargo —
  # install them the same way upstream's own packaging/package.sh does
  # for its .deb: render the icon with the just-built rustgis-cli (its
  # `logo` subcommand draws RustGIS's own vector logo, the one way to get
  # a matching icon without vendoring a PNG by hand), then install the
  # .desktop entry and the MIME type from the source tree.
  postInstall = ''
    for s in 32 64 128 256 512; do
      mkdir -p "$out/share/icons/hicolor/''${s}x''${s}/apps"
      "$out/bin/rustgis-cli" logo "$out/share/icons/hicolor/''${s}x''${s}/apps/rustgis.png" --size "$s"
    done
    install -Dm644 ${src}/packaging/linux/rustgis.desktop $out/share/applications/rustgis.desktop
    install -Dm644 ${src}/packaging/linux/rustgis-mime.xml $out/share/mime/packages/rustgis.xml
  '';

  postFixup = ''
    wrapProgram $out/bin/rustgis \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs}
  '';

  meta = {
    description = "Fast, free and open-source GIS for mapping, analysing and sharing geospatial data";
    homepage = "https://rustgis.app";
    changelog = "https://github.com/opengeos/RustGIS/releases/tag/v${version}";
    license = lib.licenses.asl20;
    mainProgram = "rustgis";
    platforms = lib.platforms.linux;
  };
}
