{
  lib,
  callPackage,
  writeShellApplication,
  ollama-rocm,
  opencode,
  gum,
  curl,
  coreutils,
  gnugrep,
  gawk,
  diffutils,
}:

# Local-LLM workspace: pick an Ollama model, then drive it with OpenCode.
#
# The whole pipeline — model server, downloaded weights and agent — runs
# inside one bubblewrap jail. That is stricter than it looks: the sandbox
# shares the network namespace, so OpenCode reaches ollama over 127.0.0.1
# without either of them being able to see the user's files.
#
# gpuCompute exposes /dev/kfd and the render nodes, which ROCm needs. Without
# them ollama silently falls back to CPU inference and a 14B model becomes
# unusable, so this is the one wrapper that deliberately hands the sandbox a
# real device.
let
  pickModel = writeShellApplication {
    name = "pick-model";
    runtimeInputs = [
      ollama-rocm # ROCm-accelerated inference runtime
      opencode # the TUI agent itself
      gum # interactive terminal menus
      curl # server health checks
      coreutils # sleep, seq, printf, mkdir, mktemp
      gnugrep # local model matching
      gawk # menu row parsing
      diffutils # cmp, for the opencode.json backup check
    ];
    # Script lives in dotfiles/ rather than inline here, per the repo rule
    # that Nix files do not embed code. writeShellApplication supplies its
    # own shebang and `set -euo pipefail`.
    text = lib.removePrefix "#!/usr/bin/env bash\n" (
      builtins.readFile ../../../dotfiles/scripts/pick-model.sh
    );
  };
in
callPackage ./mk-sandboxed.nix { } {
  name = "llm-sandboxed";
  command = "pick-model";
  exe = "${pickModel}/bin/pick-model";
  aliases = [ "llm" ];
  gpuCompute = true;
  stateDirs = [
    # Downloaded weights — tens of GB, kept out of the default ~/.ollama so
    # this workspace's models are separable from any system ollama.
    ".local/share/ollama_project_models"
    ".local/state/ollama"
    ".local/share/opencode"
    ".config/opencode"
    ".cache/opencode"
  ];
  meta.description = "Local Ollama + OpenCode workspace, bubblewrap-sandboxed";
}
