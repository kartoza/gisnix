## PCRaster — raster-based environmental modelling framework
## (pcrcalc, aguila, and the `pcraster` Python package).
##
## First Nix packaging of PCRaster (not in nixpkgs as of 2026-09); the
## recipe mirrors the conda-forge feedstock
## (https://github.com/conda-forge/pcraster-feedstock).
##
## This file must be called from a *Python package set* scope
## (e.g. `python3Packages.callPackage` or the `ps` handed to QGIS's
## `extraPythonPackages`), so the compiled bindings always match the
## interpreter that will import them. See
## software/desktop/gis/qgis-python-extras.nix for the QGIS wiring.
{
  lib,
  stdenv,
  fetchurl,
  fetchFromGitHub,
  fetchgit,
  cmake,
  ninja,
  boost,
  gdal,
  xercesc,
  ncurses,
  libGL,
  libGLU,
  libsForQt5,
  # From the Python package set:
  python,
  pybind11,
  numpy,
  toPythonModule,
  # Aguila is the Qt visualisation tool; disable for a leaner headless build.
  withAguila ? true,
}:

let
  # PCRaster's CMake uses CPM/FetchContent to git-clone dependencies at
  # configure time, which cannot work in the sandbox. We pre-fetch them at
  # the commits pinned in environment/cmake/PCRaster{,Configuration}.cmake
  # and drop them into build/_deps/<name>-src (see preConfigure), with
  # FETCHCONTENT_FULLY_DISCONNECTED telling CMake they are already there.
  # When bumping the version, re-check both cmake files for CPMAddPackage
  # calls — note the shorthand "gh:owner/repo#commit" form counts too.

  # rasterformat — PCRaster's own raster file-format library, declared via
  # CPM shorthand in PCRaster.cmake. Missing this only *warns* at configure
  # (CMP0170 defaults to WARN) and then fails at generate with
  # 'Target "pcraster::raster_format" not found'.
  rasterformatSrc = fetchFromGitHub {
    owner = "pcraster";
    repo = "rasterformat";
    rev = "d5d1c5199607b5ef9a12472eec5b018d5e18693f";
    sha256 = "01rrz391n217k066ar3cr6piznpngbgv7ck4jymlrxb5j6kvsr1s";
  };

  # fern — multicore field algebra library (only used by the multicore
  # module). Its devbase submodule is fetched separately below because
  # GitHub source tarballs exclude submodules.
  fernSrc = fetchFromGitHub {
    owner = "geoneric";
    repo = "fern";
    rev = "70c9a14cc6751809521e48e827933f00e2e13a47";
    sha256 = "01nj0jz3fv86qjkbznzkjzlzzs6aa1a57y404837nbdplf1w2spa";
  };
  # devbase — fern's cmake module submodule, at the commit fern pins.
  devbaseSrc = fetchFromGitHub {
    owner = "geoneric";
    repo = "devbase";
    rev = "0aa1104109253d9d12a58d98155f6c7feb6b28ce";
    sha256 = "1a4s3v504glvirpcvdc9avqlm6kccdlla8l3ngmm24jclcw3v8lq";
  };
  # xsd — CodeSynthesis XSD, headers only (DOWNLOAD_ONLY in CPM); CMake
  # patches one header in the tree, hence the writable copy in preConfigure.
  xsdSrc = fetchgit {
    url = "https://git.codesynthesis.com/xsd/xsd.git";
    rev = "538fb327e13c3c9d3e7ae4a7dd06098d12667f2a";
    sha256 = "1kgrhkq4z1lka7vd9z8ay7lxkvlzim16jxzjlggffphmg68d29ll";
    fetchSubmodules = false;
  };
in
toPythonModule (
  stdenv.mkDerivation (finalAttrs: {
    pname = "pcraster";
    version = "4.4.3";

    src = fetchurl {
      url = "https://pcraster.geo.uu.nl/pcraster/packages/src/pcraster-${finalAttrs.version}.tar.bz2";
      # Verified against the upstream tarball and the conda-forge feedstock.
      sha256 = "0c283d25b76c5dc4ca926261629d9cfd70dd9cbca8e0beadae022e1caa0d2bdd";
    };

    nativeBuildInputs = [
      cmake
      ninja
      # qtbase's setup hook insists on this even for the non-GUI targets.
      libsForQt5.wrapQtAppsHook
    ];

    buildInputs = [
      boost
      gdal
      xercesc
      ncurses
      python
      pybind11
      numpy
      # Qt Core/Sql/Xml are required even without Aguila.
      libsForQt5.qtbase
    ]
    ++ lib.optionals withAguila [
      libsForQt5.qtcharts
      libGL
      libGLU
    ];

    # numpy is imported by pcraster's numpy_operations at runtime.
    propagatedBuildInputs = [ numpy ];

    # On CMake >= 3.28, CPM fetches DOWNLOAD_ONLY packages (xsd) through the
    # direct multi-argument form of FetchContent_Populate, which ignores
    # FETCHCONTENT_FULLY_DISCONNECTED and always downloads. Drop the xsd
    # CPMAddPackage call entirely — the tree it would fetch is staged in
    # preConfigure, and the rest of the CMake only touches it through the
    # hardcoded _deps/xsd-src path (the xsd compiler is never run; generated
    # sources ship in the tarball). fern is fine: it goes through
    # FetchContent_MakeAvailable, which honours the disconnected flag.
    postPatch = ''
            substituteInPlace environment/cmake/PCRasterConfiguration.cmake \
              --replace-fail 'CPMAddPackage(
        NAME xsd
        GIT_REPOSITORY https://git.codesynthesis.com/xsd/xsd.git
        GIT_TAG 538fb327e13c3c9d3e7ae4a7dd06098d12667f2a
        DOWNLOAD_ONLY YES
      )' '# xsd source pre-staged by Nix in _deps/xsd-src'
    '';

    # Stage the pre-fetched CPM/FetchContent sources where CMake expects
    # them (${CMAKE_BINARY_DIR}/_deps/<name>-src — the cmake hook's build
    # dir is ./build). Copies must be writable: PCRaster's CMake patches
    # files inside both fern-src and xsd-src.
    preConfigure = ''
      mkdir -p build/_deps
      cp -r --no-preserve=mode ${rasterformatSrc} build/_deps/rasterformat-src
      cp -r --no-preserve=mode ${fernSrc} build/_deps/fern-src
      mkdir -p build/_deps/fern-src/devbase
      cp -r --no-preserve=mode ${devbaseSrc}/. build/_deps/fern-src/devbase/
      cp -r --no-preserve=mode ${xsdSrc} build/_deps/xsd-src
    '';

    cmakeFlags = [
      # Use the sources staged in preConfigure instead of cloning at
      # configure time (no network in the sandbox).
      "-DFETCHCONTENT_FULLY_DISCONNECTED=ON"
      # -march=native breaks reproducibility and portable binaries.
      "-DPCRASTER_WITH_FLAGS_NATIVE=OFF"
      "-DPython3_EXECUTABLE=${python.interpreter}"
      "-DPython3_FIND_STRATEGY=LOCATION"
      # Install the python package straight into this interpreter's
      # site-packages layout instead of upstream's $prefix/python.
      "-DPCRASTER_PYTHON_INSTALL_DIR=${placeholder "out"}/${python.sitePackages}"
      (lib.cmakeBool "PCRASTER_BUILD_AGUILA" withAguila)
      (lib.cmakeBool "PCRASTER_WITH_OPENGL" withAguila)
    ];

    # Upstream sets INSTALL_RPATH "$ORIGIN/../../lib" on the pybind11
    # extension, which only resolves in conda's layout. Point everything at
    # $out/lib explicitly so `import pcraster` finds libpcraster*.so.
    postFixup = ''
      while IFS= read -r -d "" elf; do
        patchelf --add-rpath "$out/lib" "$elf" 2>/dev/null || true
      done < <(find "$out/bin" "$out/${python.sitePackages}" -type f \
                 \( -name '*.so' -o -perm -0100 \) -print0)
    '';

    # Prove the bindings import against this exact interpreter (runs after
    # fixupPhase, so the patched rpath above is what gets exercised).
    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      PYTHONPATH="$out/${python.sitePackages}:$PYTHONPATH" \
        ${python.interpreter} -c "import pcraster; import pcraster.framework"
      runHook postInstallCheck
    '';

    meta = {
      description = "Environmental modelling framework for spatio-temporal raster analysis";
      homepage = "https://pcraster.geo.uu.nl";
      changelog = "https://pcraster.geo.uu.nl/pcraster/latest/documentation/pcraster_project/changes.html";
      license = lib.licenses.gpl3Only;
      platforms = lib.platforms.linux;
      mainProgram = "pcrcalc";
    };
  })
)
