{ pkgs, ... }:
{
  # Claude Code AI assistant for terminal, bubblewrap-sandboxed
  environment.systemPackages = [
    pkgs.claude-sandboxed
  ];

  # claude-code (wrapped by claude-sandboxed) is unfree, so it must be named in
  # the allow-list or a host taking terminal-ai fails to evaluate. See
  # software/services/system/unfree.nix.
  kartoza.unfreePackages = [ "claude-code" ];
}
