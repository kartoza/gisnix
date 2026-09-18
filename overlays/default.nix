# Custom overlays for additional packages
{ inputs, ... }:
let
  # See overlays/patch-openrazer.nix for why this exists.
  patchOpenrazer = import ./patch-openrazer.nix;
in
[
  (final: prev: {
    # nixos-utils from the shared flake input.
    nixos-utils = inputs.nixos-utils.packages.${final.stdenv.hostPlatform.system}.default;
    kartoza-plymouth-theme = inputs.kartoza-plymouth-theme.packages.${final.stdenv.hostPlatform.system}.default;
    # QGIS "Spatial without Compromise" Plymouth splash (theme dir: qgis).
    qgis-plymouth-theme =
      inputs.kartoza-plymouth-theme.packages.${final.stdenv.hostPlatform.system}.qgis-plymouth;
    kartoza-grub-themes = inputs.kartoza-grub-themes.${final.stdenv.hostPlatform.system}.default;

    # ZFS backup tool with Bubble Tea TUI
    zfs-backup = inputs.zfs-backup.packages.${final.stdenv.hostPlatform.system}.default;

    # wlgif — region-to-GIF Wayland screen recorder (upstream flake package,
    # already wrapped with slurp/wf-recorder/ffmpeg/pipewire + GStreamer
    # plugin paths). Its default wlroots backend cannot work under
    # cosmic-comp (no zwlr_screencopy_unstable_v1); only its portal backend
    # functions there.
    wlgif = inputs.wlgif.packages.${final.stdenv.hostPlatform.system}.default;

    # Remote ZFS boot-unlock for encrypted-root hosts. Generic dispatcher;
    # per-host wrapper scripts (naming a real hostname) belong in your own
    # deployment, not here.
    unlock-host = final.writeShellApplication {
      name = "unlock-host";
      runtimeInputs = [
        final.openssh
        final.iputils
      ];
      text = builtins.readFile ../dotfiles/scripts/unlock-host.sh;
    };

    # Baboon — terminal typing practice application
    baboon = inputs.baboon.packages.${final.stdenv.hostPlatform.system}.default;

    # Gatus Monitor - system tray app for monitoring Gatus health check endpoints
    gatus-monitor = inputs.gatus-monitor.packages.${final.stdenv.hostPlatform.system}.default;

    # Bubblewrapped AI applications. All generated from the one jail
    # definition in ./pkgs/ai/mk-sandboxed.nix — add new tools there rather
    # than copying a wrapper.
    claude-sandboxed = final.callPackage ./pkgs/ai/claude-sandboxed.nix { };
    # agy-sandboxed: Antigravity CLI (agy) from jacopone/antigravity-nix,
    # also exposed as `gemini-cli` and `gemini` for backward compatibility.
    agy-sandboxed = final.callPackage ./pkgs/ai/agy-sandboxed.nix { inherit inputs; };
    antigravity-sandboxed = final.callPackage ./pkgs/ai/antigravity-sandboxed.nix { };
    opencode-sandboxed = final.callPackage ./pkgs/ai/opencode-sandboxed.nix { };
    llm-sandboxed = final.callPackage ./pkgs/ai/llm-sandboxed.nix { };

    # PCRaster — raster-based environmental modelling (pcrcalc, aguila,
    # python bindings). Not in nixpkgs; local vendored derivation modelled
    # on the conda-forge feedstock. The QGIS modules build their own copies
    # against each QGIS variant's python via
    # software/desktop/gis/qgis-python-extras.nix; this one is the
    # standalone build against stable pkgs for shell/CLI use.
    pcraster = final.python3Packages.callPackage ./pkgs/pcraster/package.nix { };

    # Whitebox Workflows python backend (binary PyPI wheel, MIT/Apache-2.0).
    # Same story as pcraster: the QGIS variants get their own copies.
    whitebox-workflows = final.python3Packages.callPackage ./pkgs/whitebox-workflows/package.nix { };

    # discourse-tui — TUI Discourse-forum browser, not in nixpkgs.
    discourse-tui = final.callPackage ./pkgs/discourse-tui/package.nix { };

    # perch — terminal Mastodon/Bluesky client, not in nixpkgs.
    # GPL-3.0-or-later.
    perch = final.callPackage ./pkgs/perch/package.nix { };

    # siggy — terminal Signal client (wraps signal-cli), not in nixpkgs.
    # AGPL-3.0-only — see overlays/pkgs/siggy/package.nix for the license
    # note, the architecture, and the git-dependency outputHashes this one
    # carries that discourse-tui/perch do not.
    siggy = final.callPackage ./pkgs/siggy/package.nix { };

    # Use latest kitty from nixpkgs-unstable
    kitty =
      (import inputs.nixpkgs-unstable {
        system = final.stdenv.hostPlatform.system;
        config.allowUnfree = true;
      }).kitty;

    # Pin kanata to nixpkgs-unstable (1.12.0+). Stable lacks `defhands` /
    # `tap-hold-opposite-hand-release`. The -with-cmd build (same package,
    # `withCmd = true`) is needed for any config using a `cmd-output-keys`
    # action; the NixOS kanata service uses pkgs.kanata by default, so this
    # pins every instance.
    kanata =
      (import inputs.nixpkgs-unstable {
        system = final.stdenv.hostPlatform.system;
        config.allowUnfree = false;
      }).kanata-with-cmd;

    # Pin satty to nixpkgs-unstable (0.22.0+) for save-as directory memory.
    satty =
      (import inputs.nixpkgs-unstable {
        system = final.stdenv.hostPlatform.system;
        config.allowUnfree = false;
      }).satty;

    # Use latest COSMIC desktop packages from nixpkgs-unstable, so
    # services.desktopManager.cosmic uses the latest versions.
    inherit
      (import inputs.nixpkgs-unstable {
        system = final.stdenv.hostPlatform.system;
        config.allowUnfree = false;
      })
      cosmic-applets
      cosmic-app-library
      cosmic-bg
      cosmic-comp
      cosmic-edit
      cosmic-files
      cosmic-greeter
      cosmic-icons
      cosmic-idle
      cosmic-initial-setup
      cosmic-launcher
      cosmic-monitor
      cosmic-notifications
      cosmic-osd
      cosmic-panel
      cosmic-player
      cosmic-randr
      cosmic-reader
      cosmic-screenshot
      cosmic-session
      cosmic-settings
      cosmic-settings-daemon
      cosmic-store
      cosmic-term
      cosmic-wallpapers
      cosmic-workspaces-epoch
      cosmic-ext-applet-sysinfo
      cosmic-ext-applet-weather
      # COSMIC's to-do app is published in nixpkgs as bare `tasks`.
      tasks
      xdg-desktop-portal-cosmic
      libcosmicAppHook
      ;

    # Wrap signal-desktop to use kwallet6 for credential storage
    signal-desktop = prev.signal-desktop.overrideAttrs (oldAttrs: {
      nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ final.makeWrapper ];
      postFixup = (oldAttrs.postFixup or "") + ''
        wrapProgram $out/bin/signal-desktop \
          --add-flags "--password-store=kwallet6"
      '';
    });

  })
]
