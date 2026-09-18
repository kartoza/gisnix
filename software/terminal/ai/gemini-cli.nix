{ pkgs, ... }:
{
  # Antigravity CLI (agy) from jacopone/antigravity-nix, bubblewrap-sandboxed.
  # Also exposed as `gemini-cli` and `gemini` for backward compatibility with
  # old muscle memory / scripts. The old Google gemini-cli wrapper is replaced
  # by this package since agy supersedes it.
  environment.systemPackages = [
    pkgs.agy-sandboxed
  ];
}
