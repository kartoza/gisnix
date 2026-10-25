# super-stt (https://github.com/jorge-menjivar/super-stt) — local speech-
# to-text daemon + CLI, replacing Handy (software/services/device/input-
# kanata/kanata-keyboard.nix) after Handy's Settings window started
# permanently white-screening (an upstream Tauri/WebKitGTK rendering bug,
# not something this fleet's config caused — not worth chasing further).
# Swap approved/requested by Tim 2026-10-25.
#
# GPL-3.0-only. The fleet's dependency policy blocks GPL/AGPL unless
# explicitly approved (see siggy/package.nix, which carries the same
# note) — approved here in the same conversation that requested the
# swap, not a silent default.
#
# Not in nixpkgs (checked: no pkgs/by-name/su/super-stt, nixpkgs master,
# 2026-10-25).
#
# WORKSPACE SUBSET: upstream is a 10-member Cargo workspace. We build
# only super-stt-daemon and super-stt-cli — the headless pieces this
# fleet actually wires up (systemd --user service + the `stt` CLI a
# keyboard shortcut invokes). super-stt-app/-cosmic-applet/-consent and
# their GUI dependency chain (libcosmic, accesskit, window_clipboard,
# cosmic-panel, ...) are never built, matching how Handy and voxtype
# before it were both plumbed in as headless pieces, not GUI apps.
#
# GIT DEPENDENCIES: `cargo vendor`/importCargoLock fetch every git
# source Cargo.lock names, regardless of which workspace members end up
# compiled — see siggy/package.nix's header for the long version of why,
# including the cautionary tale of an AI-summarized lockfile fetch
# silently dropping a dependency that only showed up as a build failure.
# The list below was ALSO built from an AI-summarized fetch (no working
# nix/cargo in the environment that wrote this), NOT a raw grep of the
# lockfile text — unlike siggy's list, it has not been cross-checked.
# Before the first real build: `grep -o 'source = "git+[^"]*"'
# Cargo.lock | sort -u` against the actual v0.2.4 tag checkout and
# confirm every unique repo+rev below is represented (and that none of
# these package names/versions have drifted — Cargo.lock is not public
# API, pin exactness matters).
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  alsa-lib,
}:
rustPlatform.buildRustPackage rec {
  pname = "super-stt";
  version = "0.2.4";

  src = fetchFromGitHub {
    owner = "jorge-menjivar";
    repo = "super-stt";
    rev = "v${version}";
    # Computed outside Nix (no working nix daemon in the sandbox that
    # wrote this) — PLACEHOLDER. Resolve on a real machine with:
    #   nix build .#super-stt 2>&1 | grep -A2 'got:'
    # and paste the "got:" hash in here.
    hash = lib.fakeHash;
  };

  cargoBuildFlags = [
    "-p"
    "super-stt-daemon"
    "-p"
    "super-stt-cli"
  ];
  cargoTestFlags = cargoBuildFlags;

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
    outputHashes = {
      # jorge-menjivar/enigo (fork of enigo-rs/enigo) — keyboard-input
      # simulation, used by the CLI's `--write` mode.
      "enigo-0.6.1" = lib.fakeHash;
      # pop-os/libcosmic.git @ ef162b8e — also covers the other crates
      # vendored from the same checkout (cosmic-config,
      # cosmic-config-derive, cosmic-theme, iced and the iced_* family).
      # GUI-only; dead weight for our -p subset, still has to vendor.
      "libcosmic-1.0.0" = lib.fakeHash;
      # wash2/accesskit @ tag cosmic-0.14. GUI-only (libcosmic's a11y
      # layer).
      "accesskit-0.22.0" = lib.fakeHash;
      # pop-os/window_clipboard.git @ tag sctk-0.20. GUI-only.
      "window_clipboard-0.1.0" = lib.fakeHash;
      # pop-os/cosmic-protocols @ 32283d7. GUI-only (cosmic-applet).
      "cosmic-protocols-0.2.0" = lib.fakeHash;
      # pop-os/cosmic-panel. GUI-only (cosmic-applet).
      "cosmic-panel-config-0.1.0" = lib.fakeHash;
      # pop-os/dbus-settings-bindings. GUI-only.
      "dbus-settings-bindings-0.1.0" = lib.fakeHash;
      # jackpot51/rust-atomicwrites. Pulled in by the GUI side's config
      # writer; the daemon/CLI may also use it for its own config file —
      # harmless either way, still needs a real hash.
      "atomicwrites-0.4.2" = lib.fakeHash;
    };
  };

  # cpal (audio I/O, super-stt-daemon's dependency) links ALSA on Linux.
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ alsa-lib ];

  meta = {
    description = "Local speech-to-text daemon and CLI (dictation)";
    homepage = "https://github.com/jorge-menjivar/super-stt";
    license = lib.licenses.gpl3Only;
    mainProgram = "super-stt-daemon";
    platforms = lib.platforms.linux;
  };
}
