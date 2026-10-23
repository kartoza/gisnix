# restream — Textual TUI front end for stream-sprout (overlays/default.nix's
# `stream-sprout`, see software/desktop/multimedia/obs.nix). Our own script,
# not an upstream package — wrapped with writePython3Bin, the same way
# find-cursor.nix wraps its own inline python, except the source here is a
# real .py file (restream.py) rather than a string embedded in a .nix file.
{ writers, python3Packages }:
writers.writePython3Bin "restream" {
  libraries = with python3Packages; [
    textual
    pyyaml
  ];
  # writers' flake8 check enforces strict PEP8 style (line length, comment
  # formatting, ambiguous names, operator-placement nits) that nothing
  # else in this repo's Python follows (see utils/*.py) — none of it is a
  # real defect. Ignore the whole pycodestyle families (E, W) rather than
  # chase one code at a time; keep pyflakes' F-codes (unused imports,
  # undefined names, redefinitions) enforced — those catch real bugs.
  flakeIgnore = [
    "E"
    "W"
  ];
} (builtins.readFile ./restream.py)
