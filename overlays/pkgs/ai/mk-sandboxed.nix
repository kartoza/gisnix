# Factory for bubblewrap-sandboxed AI tools.
#
# Every AI assistant we ship runs inside the same jail, and the wrappers had
# drifted into five near-identical copies of ~90 lines of bash. This builds
# them from one description instead. The security properties are the contract:
#
#   * $HOME is a tmpfs — the agent sees none of the user's files.
#   * Only $(pwd) and the tool's own state dirs are writable.
#   * Refuses to start in $HOME, which would bind the whole home directory in.
#   * .env files anywhere under $(pwd) are masked with /dev/null so secrets
#     never reach the model's context.
#   * The ssh-agent socket is masked and SSH_* unset, so a compromised agent
#     cannot authenticate to this machine or any LAN/tailnet peer.
#
# The network namespace is deliberately shared: these tools need to reach
# their APIs, and the local ones need 127.0.0.1 to talk to ollama.
{
  lib,
  writeShellScriptBin,
  symlinkJoin,
  bubblewrap,
}:

{
  # Package name, and the command name users type.
  name,
  command,
  # Absolute path to the real binary to exec inside the sandbox.
  exe,
  # Extra arguments inserted before "$@".
  extraArgs ? [ ],
  # Directories under $HOME to create and bind writable (persistent state).
  stateDirs ? [ ],
  # Files under $HOME to touch and bind writable (e.g. ~/.claude.json).
  stateFiles ? [ ],
  # Extra bin names symlinked to `command`, for backward compatibility.
  aliases ? [ ],
  # Expose GPU, Wayland/X11, fonts and machine-id for graphical tools.
  gui ? false,
  # Expose the ROCm/amdgpu compute devices, for tools that run inference.
  gpuCompute ? false,
  # Ceiling on the tmpfs mounted at $HOME inside the jail, in GiB.
  #
  # This is a memory limit, not a disk limit. bwrap's --tmpfs takes the kernel
  # default when unbounded, which is 50% of RAM *per mount* — so three
  # concurrent agent sessions could each claim 46 GiB on a 92 GiB machine. With
  # swapDevices = [ ] fleet-wide there is nowhere to page it out to, so anything
  # written there is unevictable RAM until the sandbox exits. That is not
  # hypothetical: a single agent build put 36 GiB into one of these, three
  # sessions together held 66 GiB of shmem, and the kernel OOM killer started
  # killing desktop applications (Firefox, Steam) to claw memory back.
  #
  # 4 GiB is ample for the scratch these tools actually use, and bounds the
  # worst case to something the machine can survive.
  homeTmpfsGiB ? 4,
  # Directories under $HOME that must live on real disk rather than in the
  # RAM-backed tmpfs, because tools fill them without being asked to.
  #
  # The motivating case is nix. /nix/store is bound read-only and the daemon
  # socket is not bound at all, so nix inside the jail cannot use the host
  # store for writes. It does not fail — it silently falls back to a LOCAL
  # CHROOT STORE under ~/.local/share/nix/root and builds everything there.
  # On a tmpfs $HOME that is pure RAM. One agent session accumulated 36 GiB
  # this way, which is also why paths it "built" were invisible under
  # /nix/store and `nix-store -q` called them invalid.
  #
  # Binding ~/.local/share/nix from real disk moved that growth off RAM, and
  # was the wrong answer: a second nix store, unreferenced by the host, that
  # nothing garbage-collects and nothing can even delete — its paths are
  # read-only by design, so the prune below failed on every file it touched.
  # `NIX_REMOTE=daemon` below removes the fallback entirely, so there is no
  # parallel store to bind, budget or clean up.
  #
  # ~/.cache/nix stays: it is the evaluation cache, not a store, and a warm
  # one makes `nix search` and flake evaluation bearable.
  scratchDirs ? [
    ".cache/nix"
  ],
  # Subpaths of $HOME wiped when the scratch has not been pruned recently.
  # Only the evaluation cache now. The chroot store used to be listed here
  # and could never actually be removed: nix store paths are read-only, so
  # `rm -rf` fails on every file with "Permission denied" and leaves the
  # store behind. With NIX_REMOTE=daemon there is no store to prune.
  scratchPrunePaths ? [
    ".cache/nix"
  ],
  # How often to prune, in days. The check is a stat on a marker file, so it
  # costs nothing on the launches that do not prune.
  scratchPruneDays ? 7,
  # Raw extra bwrap arguments, one per list element.
  extraBwrapArgs ? [ ],
  # Extra environment variables to set inside the sandbox.
  extraEnv ? { },
  meta ? { },
}:

let
  # $HOME is a tmpfs, so every persistent path has to be created on the host
  # before bwrap binds it, or the bind target will not exist.
  mkStateDirs = lib.concatMapStringsSep "\n" (d: ''mkdir -p "$HOME/${d}"'') stateDirs;
  mkStateFiles = lib.concatMapStringsSep "\n" (f: ''
    mkdir -p "$(dirname "$HOME/${f}")"
    touch "$HOME/${f}"
  '') stateFiles;

  mkScratchDirs = lib.concatMapStringsSep "\n" (d: ''mkdir -p "$HOME/${d}"'') scratchDirs;

  # Regular cleanup, driven by the age of a marker file rather than by walking
  # the tree: `du` over a multi-GiB chroot store on every launch would be a
  # noticeable startup cost, and a stat is free.
  #
  # Runs on the HOST, before bwrap, against real paths — hence the narrow
  # scratchPrunePaths rather than a blanket wipe of $HOME.
  scratchPrune = lib.optionalString (scratchPrunePaths != [ ]) ''
    SCRATCH_MARKER="$HOME/.cache/nix/.sandbox-last-prune"
    if [ ! -e "$SCRATCH_MARKER" ] \
       || [ -n "$(find "$SCRATCH_MARKER" -maxdepth 0 -mtime +${toString scratchPruneDays} 2>/dev/null)" ]; then
      ${lib.concatMapStringsSep "\n  " (p: ''rm -rf "$HOME/${p}"'') scratchPrunePaths}
      ${lib.concatMapStringsSep "\n  " (d: ''mkdir -p "$HOME/${d}"'') scratchDirs}
      touch "$SCRATCH_MARKER"
    fi
  '';

  # Graphical tools additionally need a GPU node, the compositor socket, the
  # X11 cookie, fonts and a stable machine-id.
  guiPreamble = lib.optionalString gui ''

    # X11 cookie file (if present) so GTK apps can authenticate
    XAUTH_ARGS=""
    if [ -n "''${XAUTHORITY:-}" ] && [ -f "$XAUTHORITY" ]; then
      XAUTH_ARGS="--ro-bind $XAUTHORITY $XAUTHORITY --setenv XAUTHORITY $XAUTHORITY"
    fi
  '';

  # The bwrap invocation is assembled as a Nix LIST, then joined into one
  # backslash-continued command.
  #
  # It used to be a here-doc with ${...} holes for the optional groups. When a
  # group was empty (no extraBwrapArgs, gui = false, gpuCompute = false) the
  # hole collapsed to a blank line in the middle of the continuation. A blank
  # line ends with an unescaped newline, which TERMINATES the command — so
  # bwrap was exec'd with mount flags but no COMMAND and just printed its
  # usage. Building a list makes empty groups disappear instead of leaving a
  # line behind, so the bug cannot recur.
  bwrapArgs = [
    "--ro-bind /nix/store /nix/store"
    "--ro-bind /run/current-system/sw /run/current-system/sw"
    "--ro-bind /usr/bin/env /usr/bin/env"
    "--proc /proc"
    "--dev /dev"
    "--tmpfs /tmp"
    ''--bind "$SANDBOX_TMP" "$SANDBOX_TMP"''
    # --size applies to the NEXT --tmpfs only, so these two must stay adjacent
    # and in this order. See homeTmpfsGiB above for why the bound exists.
    "--size ${toString (homeTmpfsGiB * 1024 * 1024 * 1024)}"
    ''--tmpfs "$HOME"''
    ''--bind "$(pwd)" "$(pwd)"''
    # Empty bash arrays expand to zero words, so this vanishes when there
    # are no .env files to mask.
    ''"''${ENV_HIDE_ARGS[@]}"''
  ]
  # Persistent state: created on the host above, bound over the tmpfs $HOME.
  ++ map (p: ''--bind "$HOME/${p}" "$HOME/${p}"'') (stateDirs ++ stateFiles ++ scratchDirs)
  ++ extraBwrapArgs
  # Unquoted on purpose: empty string must disappear, non-empty must split.
  ++ [ "$GITCONFIG_ARGS" ]
  ++ lib.optionals gui [
    "--ro-bind /run/opengl-driver /run/opengl-driver"
    "--dev-bind /dev/dri /dev/dri"
    "--ro-bind /tmp/.X11-unix /tmp/.X11-unix"
    "--ro-bind /etc/machine-id /etc/machine-id"
    "--ro-bind /etc/fonts /etc/fonts"
    "$XAUTH_ARGS"
  ]
  # ROCm needs the kernel fusion driver and the render nodes. /dev/kfd is the
  # compute device; without it ollama silently falls back to CPU.
  ++ lib.optionals gpuCompute [
    "--ro-bind /run/opengl-driver /run/opengl-driver"
    "--dev-bind-try /dev/kfd /dev/kfd"
    "--dev-bind-try /dev/dri /dev/dri"
    "--ro-bind-try /sys/devices /sys/devices"
    "--ro-bind-try /sys/class/kfd /sys/class/kfd"
    "--ro-bind-try /sys/class/drm /sys/class/drm"
  ]
  ++ [
    "--ro-bind /etc/resolv.conf /etc/resolv.conf"
    "--ro-bind /etc/ssl /etc/ssl"
    "--ro-bind /etc/static /etc/static"
    "--ro-bind /etc/passwd /etc/passwd"
    "--ro-bind /etc/group /etc/group"
    ''--bind "/run/user/$(id -u)" "/run/user/$(id -u)"''
    "$SSH_DENY_ARGS"
    "--unsetenv SSH_AUTH_SOCK"
    "--unsetenv SSH_AGENT_PID"
    "--unsetenv SSH_ASKPASS"
    ''--setenv HOME "$HOME"''
    ''--setenv PATH "$PATH"''
    ''--setenv SHELL "/run/current-system/sw/bin/bash"''
    ''--setenv TERM "$TERM"''
    ''--setenv LANG "''${LANG:-en_US.UTF-8}"''
    ''--setenv COLORTERM "''${COLORTERM:-truecolor}"''
    ''--setenv XDG_RUNTIME_DIR "/run/user/$(id -u)"''
    # No parallel store. Without this, nix inside the jail cannot reach the
    # daemon socket (deliberately unbound) and quietly builds into a chroot
    # store of its own instead. Naming the daemon explicitly makes that
    # fallback impossible: nix now fails with "cannot open connection to nix
    # daemon", which is the honest answer — a sandbox that cannot write to
    # the store cannot build.
    #
    # Reading still works. /nix/store is bound read-only, so anything already
    # built runs, and evaluation is unaffected.
    "--setenv NIX_REMOTE daemon"
    ''--setenv DBUS_SESSION_BUS_ADDRESS "unix:path=/run/user/$(id -u)/bus"''
  ]
  ++ lib.optionals gui [
    ''--setenv DISPLAY "''${DISPLAY:-}"''
    ''--setenv WAYLAND_DISPLAY "''${WAYLAND_DISPLAY:-}"''
    ''--setenv XDG_SESSION_TYPE "''${XDG_SESSION_TYPE:-}"''
    ''--setenv NIXOS_OZONE_WL "''${NIXOS_OZONE_WL:-}"''
  ]
  ++ lib.mapAttrsToList (k: v: ''--setenv ${k} "${v}"'') extraEnv
  ++ [
    ''--chdir "$(pwd)"''
    "--die-with-parent"
  ];

  bwrapArgsText = lib.concatStringsSep " \\\n    " bwrapArgs;

  script = writeShellScriptBin command ''
    # Refuse to run from $HOME — it would bind-mount the entire home directory
    if [ "$(pwd)" = "$HOME" ]; then
      echo "ERROR: Do not run ${command} from your home directory ($HOME)." >&2
      echo "The bubblewrap sandbox bind-mounts \$(pwd) into the container." >&2
      echo "Running from \$HOME would expose your entire home directory." >&2
      echo "Please cd into a project directory first." >&2
      exit 1
    fi

    # Persistent state must exist on the host before bwrap binds it, because
    # $HOME inside the sandbox is a tmpfs.
    ${mkStateDirs}
    ${mkStateFiles}

    # Real-disk scratch, plus its periodic cleanup. Order matters: create the
    # directories first so the marker has somewhere to live, then prune.
    ${mkScratchDirs}
    ${scratchPrune}

    SANDBOX_TMP="/tmp/${command}-$(id -u)"
    mkdir -p "$SANDBOX_TMP"

    # SSH-credential denial. ~/.ssh is already hidden by --tmpfs "$HOME", but
    # /run/user is bound below, which would expose the live ssh-agent socket.
    # Mask the agent socket(s) and unset SSH_* so the sandboxed agent has no
    # way to authenticate to any host — it cannot ssh back into this machine
    # or reach LAN/tailnet peers.
    SSH_DENY_ARGS="--bind /dev/null /run/user/$(id -u)/ssh-agent"
    if [ -e "/run/user/$(id -u)/gnupg/S.gpg-agent.ssh" ]; then
      SSH_DENY_ARGS="$SSH_DENY_ARGS --bind /dev/null /run/user/$(id -u)/gnupg/S.gpg-agent.ssh"
    fi

    # Optional read-only mounts (only bind if they exist)
    GITCONFIG_ARGS=""
    if [ -f "$HOME/.gitconfig" ]; then
      GITCONFIG_ARGS="--ro-bind $HOME/.gitconfig $HOME/.gitconfig"
    fi
    ${guiPreamble}
    # Exclude .env files from LLM context to prevent secret leakage
    ENV_HIDE_ARGS=()
    while IFS= read -r -d "" env_file; do
      ENV_HIDE_ARGS+=("--bind" "/dev/null" "$env_file")
    done < <(find "$(pwd)" \( -name .git -o -name node_modules -o -name .venv -o -name venv -o -name target -o -name .cache -o -name .direnv \) -prune -o -type f \( -name ".env" -o -name ".env.*" -o -name "*.env" \) -print0 2>/dev/null)

    exec ${bubblewrap}/bin/bwrap \
        ${bwrapArgsText} \
        ${exe} ${lib.escapeShellArgs extraArgs} "$@"
  '';
in
symlinkJoin {
  inherit name meta;
  paths = [ script ];
  postBuild = lib.concatMapStringsSep "\n" (a: ''
    ln -s $out/bin/${command} $out/bin/${a}
  '') aliases;
}
