{ pkgs, ... }:
{
  # Antigravity (VS Code fork Electron IDE), bubblewrap-sandboxed
  environment.systemPackages = [
    pkgs.antigravity-sandboxed
  ];
}
