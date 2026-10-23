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
  # writers' flake8 check enforces PEP8's 79-column line limit, which
  # nothing else in this repo's Python follows (see utils/*.py) — not a
  # real defect, just a stricter default than our house style.
  flakeIgnore = [ "E501" ];
} (builtins.readFile ./restream.py)
