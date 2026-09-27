{ pkgs, ... }:
{
  # Antigravity CLI (agy) from jacopone/antigravity-nix, bubblewrap-sandboxed.
  # Also exposed as `gemini-cli` and `gemini` for backward compatibility with
  # old muscle memory / scripts. The old Google gemini-cli wrapper is replaced
  # by this package since agy supersedes it.
  environment.systemPackages = [
    pkgs.agy-sandboxed
  ];

  # agy (google-antigravity-cli, from the antigravity-nix flake, wrapped by
  # agy-sandboxed) is Google-proprietary and unfree; allow-list it or a host
  # taking terminal-ai fails to evaluate. If this name is not the one nixpkgs'
  # `lib.getName` reports, the all-bundles eval check names the exact string.
  kartoza.unfreePackages = [ "google-antigravity-cli" ];
}
