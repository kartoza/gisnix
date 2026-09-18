{ callPackage, opencode }:

# OpenCode TUI agent wrapped in bubblewrap.
#
# Note the network namespace is shared (as for every wrapper here), which is
# what lets OpenCode reach a provider — including a local ollama on
# 127.0.0.1. `pick-model` is the usual entry point; this is the bare agent for
# when you already have an opencode.json in the project.
callPackage ./mk-sandboxed.nix { } {
  name = "opencode-sandboxed";
  command = "opencode";
  exe = "${opencode}/bin/opencode";
  stateDirs = [
    ".local/share/opencode"
    ".config/opencode"
    ".cache/opencode"
  ];
  meta.description = "OpenCode TUI agent, bubblewrap-sandboxed";
}
