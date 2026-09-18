{
  pkgs,
  lib,
  hostConfig,
  ...
}:
let
  # Opt-in per host: set `localLlm = true;` in hosts/<host>/config.nix.
  #
  # This is gated rather than always-on because ollama-rocm drags the whole
  # ROCm stack into the system closure — several GB. That is fine on a machine
  # with an AMD GPU to point it at, and pure waste on a server or a lightweight
  # laptop, so hosts ask for it explicitly.
  enabled = hostConfig.localLlm or false;
in
{
  # Self-hosted LLM workspace, bubblewrap-sandboxed like the rest of the AI
  # tooling:
  #
  #   pick-model  (alias: llm)  pick an Ollama model, then open OpenCode on it
  #   opencode                  the bare agent, for a project that already has
  #                             an opencode.json
  #
  # Both run with $HOME as a tmpfs; only $(pwd) and their own state dirs are
  # writable. See overlays/pkgs/ai/mk-sandboxed.nix.
  environment.systemPackages = lib.optionals enabled [
    pkgs.llm-sandboxed
    pkgs.opencode-sandboxed
  ];
}
