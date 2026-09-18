{ pkgs, ... }:
{
  # Claude Code AI assistant for terminal, bubblewrap-sandboxed
  environment.systemPackages = [
    pkgs.claude-sandboxed
  ];
}
