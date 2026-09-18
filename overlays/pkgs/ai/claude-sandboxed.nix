{ callPackage, claude-code }:

# Claude Code wrapped in bubblewrap for filesystem sandboxing.
# Only CWD + ~/.claude state are writable; see mk-sandboxed.nix for the
# full set of security properties.
callPackage ./mk-sandboxed.nix { } {
  name = "claude-sandboxed";
  command = "claude";
  exe = "${claude-code}/bin/claude";
  stateDirs = [
    ".claude"
    # MCP logs and session cache
    ".cache/claude-cli-nodejs"
  ];
  # Auth state; must exist as a file before it can be bind-mounted.
  stateFiles = [ ".claude.json" ];
  meta.description = "Claude Code, bubblewrap-sandboxed";
}
