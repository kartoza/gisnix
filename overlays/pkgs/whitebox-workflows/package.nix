## Whitebox Workflows — the Python backend the `whitebox_workflows_qgis`
## plugin needs. Upstream publishes no source distribution, only binary
## wheels (MIT OR Apache-2.0), so we repackage the manylinux wheel instead
## of letting the plugin pip-install into ~/.local at runtime.
##
## The wheel is cp39-abi3: one artefact works for every CPython >= 3.9, so
## this same file serves all QGIS python sets. Must be called from a Python
## package set scope (`python3Packages.callPackage` or the `ps` handed to
## QGIS's `extraPythonPackages`).
##
## Update: bump version, then take the new sha256 from
##   curl -s https://pypi.org/pypi/whitebox-workflows/json | jq '.urls[]'
{
  lib,
  stdenv,
  buildPythonPackage,
  fetchPypi,
  autoPatchelfHook,
}:

buildPythonPackage rec {
  pname = "whitebox-workflows";
  version = "2.0.6";
  format = "wheel";

  src = fetchPypi {
    pname = "whitebox_workflows";
    inherit version format;
    dist = "cp39";
    python = "cp39";
    abi = "abi3";
    platform = "manylinux_2_17_x86_64.manylinux2014_x86_64";
    sha256 = "866d802880aa77051a8321d9976c134e116d9e07ec686cfd928bf687f480096e";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  # The wheel declares no python dependencies (compiled Rust extension).
  pythonImportsCheck = [ "whitebox_workflows" ];

  meta = {
    description = "Whitebox Workflows for Python - geospatial data analysis backend";
    homepage = "https://www.whiteboxgeo.com/whitebox-workflows-for-python/";
    license = with lib.licenses; [
      mit
      asl20
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
  };
}
