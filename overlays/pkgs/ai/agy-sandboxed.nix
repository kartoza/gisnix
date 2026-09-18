{
  callPackage,
  stdenv,
  inputs,
}:

# Antigravity CLI (agy) wrapped in bubblewrap for filesystem sandboxing.
# Exposes three command names: `agy`, `gemini-cli` and `gemini` (the last two
# replace the old Google gemini-cli wrapper, which agy supersedes).
# agy is pulled from jacopone/antigravity-nix (auto-updating, 3x/week).
let
  agyPkg = inputs.antigravity-nix.packages.${stdenv.hostPlatform.system}.google-antigravity-cli;
in
callPackage ./mk-sandboxed.nix { } {
  name = "agy-sandboxed";
  command = "agy";
  exe = "${agyPkg}/bin/agy";
  stateDirs = [ ".gemini" ];
  # Previously these were symlinked to a non-existent `antigravity` binary,
  # which produced dangling links in the system path.
  aliases = [
    "gemini-cli"
    "gemini"
  ];
  meta.description = "Antigravity CLI (agy), bubblewrap-sandboxed";
}
