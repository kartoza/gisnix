## Extra geospatial Python packages injected into every QGIS build.
##
## Each QGIS variant embeds its own Python (nixpkgs stable, unstable, or
## the QGIS flake's pin), so compiled bindings must be built per variant
## against that exact interpreter. This helper takes the `ps` python
## package set that `extraPythonPackages` hands each QGIS module and
## builds the packages with `ps.callPackage` — never reuse a copy built
## against another pkgs set, or the site-packages path and ABI won't
## match. Variants that share a python set (latest + LTR on unstable)
## deduplicate to a single store path automatically.
##
## Usage in a QGIS module:
##   let qgisPythonExtras = import ./qgis-python-extras.nix;
##   ...
##   extraPythonPackages = ps: (with ps; [ numpy ... ]) ++ qgisPythonExtras ps;
ps: [
  # PCRaster — pcrcalc/aguila CLIs land on QGIS's PATH, the `pcraster`
  # python package on its PYTHONPATH (for the PCRaster Tools plugin and
  # the python console).
  (ps.callPackage ../../../overlays/pkgs/pcraster/package.nix { })
  # Whitebox Workflows backend for the whitebox_workflows_qgis plugin,
  # replacing its pip-install-into-~/.local bootstrap.
  (ps.callPackage ../../../overlays/pkgs/whitebox-workflows/package.nix { })
]
