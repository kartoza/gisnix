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
# UNVERIFIED: no working nix daemon here to build with (see this repo's
# sandbox-workflow notes), so this derivation has never actually been
# built. Everything above was confirmed by reading the real source tree
# at the v0.2.0 tag (Cargo.toml, Cargo.lock, apps/rustgis/Cargo.toml, the
# AUR/package.sh packaging scripts) rather than guessed — but "the source
# says X" is not the same as "it built". Build this for real before
# trusting it; if the GUI doesn't come up, LD_LIBRARY_PATH coverage above
# is the first thing to check.
#
# Upstream: https://github.com/opengeos/RustGIS
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  makeWrapper,
  libxkbcommon,
  wayland,
  vulkan-loader,
  libGL,
  xorg,
  fontconfig,
  freetype,
}:
let
  runtimeLibs = [
    libxkbcommon
    wayland
    vulkan-loader
    libGL
    xorg.libX11
    xorg.libXcursor
    xorg.libXi
    xorg.libXrandr
    fontconfig
    freetype
  ];
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
