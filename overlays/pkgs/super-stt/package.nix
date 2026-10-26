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
# That exact thing happened here on the first pass: the list below was
# originally built from an AI-summarized fetch, not a raw grep, and it
# both missed real dependencies (cryoglyph, freedesktop-icons,
# smithay-clipboard, softbuffer, winit) and got window_clipboard's
# version wrong (0.1.0 vs the real 0.4.1). Re-derived 2026-10-25 against
# the real v0.2.4 tag's Cargo.lock via:
#   curl -fsSL https://raw.githubusercontent.com/jorge-menjivar/super-stt/v0.2.4/Cargo.lock \
#     | awk '/^\[\[package\]\]/{n="";v=""} /^name = /{n=$0;sub(/^name = "/,"",n);sub(/"$/,"",n)} \
#            /^version = /{v=$0;sub(/^version = "/,"",v);sub(/"$/,"",v)} \
#            /^source = "git\+/{print n"-"v"\t"$0}'
# 14 unique repo+rev source strings exist; one representative
# name-version below per unique source is enough (the key just needs
# to resolve to that source's URL — nix doesn't need every crate that
# shares a source listed). Re-run that grep against any version bump
# and recheck before touching this file again.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  alsa-lib,
  dbus,
  libxkbcommon,
  runCommand,
  python3,
}:
let
  version = "0.2.4";

  src = fetchFromGitHub {
    owner = "jorge-menjivar";
    repo = "super-stt";
    rev = "v${version}";
    # Computed outside Nix (no working nix daemon in the sandbox that
    # wrote this) — PLACEHOLDER. super-stt isn't a flake package output
    # (the overlay is only applied inside NixOS configs) — resolve on a
    # real machine with nix-config/claude.sh, or by hand via:
    #   nix build --impure --no-link -L --expr \
    #     'let f = builtins.getFlake (toString ./.); in
    #      (import f.inputs.nixpkgs { system = builtins.currentSystem;
    #        overlays = import ./overlays { inherit (f) inputs; }; }).super-stt'
    # and paste each "got:" hash in here, one fixed-output derivation
    # at a time.
    hash = "sha256-vHTwYhC5PbnXd+Nhhr1V/Md5RSEMI3dDWbXoS+Nu0O8=";
  };

  # See dedupe-cargo-lock.py's docstring for why this exists: libcosmic's
  # Cargo.lock has 5 crates listed twice under two different source
  # URLs for the same commit, which collides when nixpkgs vendors them
  # ("Permission denied" on the second symlink). A structure-aware
  # script, not giant verbatim string literals, so it keeps working if
  # the lockfile's exact text shifts on a version bump (and loudly fails
  # if the 5 names it expects to drop ever go missing).
  patchedCargoLock = runCommand "super-stt-Cargo.lock" { } ''
    ${python3}/bin/python3 ${./dedupe-cargo-lock.py} ${src}/Cargo.lock > $out
  '';
in
rustPlatform.buildRustPackage rec {
  pname = "super-stt";
  inherit version src;

  # Adds `provision-model`: installs/selects/loads this fleet's default
  # local speech model via the daemon's HTTP API, so dictation works
  # declaratively with no GUI app and no manual per-host setup. See the
  # patch file's own header for the full design rationale (why the CLI
  # auto-approves as a "first-party" client but the GUI app's consent
  # flow doesn't exist in our headless build, why it needs its own
  # AppId/scopes, and the exact daemon endpoints it drives).
  patches = [ ./super-stt-cli-provision.patch ];

  cargoBuildFlags = [
    "-p"
    "super-stt-daemon"
    "-p"
    "super-stt-cli"
  ];
  # super-stt-cli's integration tests (cmd_basic.rs) spawn the real
  # daemon and wait for its HTTP socket to appear — that needs a live
  # runtime environment (socket binding, audio devices) the sandboxed
  # nix build doesn't have, not something a code change could fix.
  # Found 2026-10-26 after the first successful compile: 3 of these
  # tests time out waiting 120s for a socket that will never appear in
  # the build sandbox.
  doCheck = false;

  cargoLock = {
    # Can't point this at "${src}/Cargo.lock" directly and fix the
    # duplicate-stanza issue via postPatch: nixpkgs builds the vendor
    # derivation straight from cargoLock.lockFile before the package's
    # own patch phases ever run, so a postPatch edit would be too late.
    # patchedCargoLock (defined above, via dedupe-cargo-lock.py) fixes
    # the content before cargoLock ever sees it.
    lockFile = patchedCargoLock;
    outputHashes = {
      # jorge-menjivar/enigo (fork of enigo-rs/enigo) — keyboard-input
      # simulation, used by the CLI's `--write` mode. The one git dep
      # in this list that actually gets compiled into our -p subset.
      "enigo-0.6.1" = "sha256-5eC73e2riiWuDpW4qc0kd0dxHfCCPbANpKYaQpNRkII=";
      # pop-os/libcosmic.git @ ef162b8e — also covers the other crates
      # vendored from the same checkout (build_helpers, cosmic-config,
      # cosmic-config-derive, cosmic-theme, iced and the iced_* family).
      # GUI-only; dead weight for our -p subset, still has to vendor.
      "libcosmic-1.0.0" = "sha256-2By9fKPXsNhoCP1Npyoi3bG8a8Bb15cEXewK6ea0WWo=";
      # wash2/accesskit @ tag cosmic-0.14 — also covers
      # accesskit_atspi_common/_consumer/_macos/_unix/_windows/_winit
      # from the same checkout. GUI-only (libcosmic's a11y layer).
      "accesskit-0.22.0" = "sha256-pP9CyiV1zIONQ7vbl5MkMtilemSPrHaZ0c/SyR+lb0k=";
      # pop-os/window_clipboard.git @ tag sctk-0.20 — also covers
      # clipboard_macos/_wayland/_x11, dnd, and mime from the same
      # checkout. GUI-only. (Real version is 0.4.1, not 0.1.0 — the
      # first AI-summarized pass got this one wrong.)
      "window_clipboard-0.4.1" = "sha256-WO3JFbE+6ESRAfkxrnEFeZyGuhUHLOKOVHcGQyHwoK0=";
      # pop-os/cosmic-protocols @ 32283d7 — also covers
      # cosmic-client-toolkit. GUI-only (cosmic-applet).
      "cosmic-protocols-0.2.0" = "sha256-LUAmB+3+doRZOJbVURaIInaQuV/LXCKfoWHA28ihAMo=";
      # pop-os/cosmic-panel — also covers xdg-shell-wrapper-config.
      # GUI-only (cosmic-applet).
      "cosmic-panel-config-0.1.0" = "sha256-3nIlsngBTH7WZGVGjSeVvJUY3rWvORnfby0TfgiRWLg=";
      # pop-os/dbus-settings-bindings.git — the crate it publishes is
      # named cosmic-settings-daemon, not the repo name. GUI-only.
      "cosmic-settings-daemon-0.1.0" = "sha256-LYIR+qK+hCBVV+bfVWz2jvH5fGvfNTcryKqfe5n8Gog=";
      # jackpot51/rust-atomicwrites. Pulled in by the GUI side's config
      # writer; the daemon/CLI may also use it for its own config file —
      # harmless either way, still needs a real hash.
      "atomicwrites-0.4.2" = "sha256-QZSuGPrJXh+svMeFWqAXoqZQxLq/WfIiamqvjJNVhxA=";
      # iced-rs/cryoglyph.git @ e429a025 — libcosmic's text-shaping
      # crate. GUI-only. Missed entirely by the first AI-summarized pass.
      "cryoglyph-0.1.0" = "sha256-10JUHl1ktbqLaReuiU3HPa4r2KvsoryyJoF3BFoge3U=";
      # pop-os/freedesktop-icons (published as cosmic-freedesktop-icons).
      # GUI-only. Missed entirely by the first AI-summarized pass.
      "cosmic-freedesktop-icons-0.4.0" = "sha256-tPriTi5L0mFMHjo5xpF5cmKGHqlX3WUO7EZAgVdBpS4=";
      # pop-os/smithay-clipboard @ tag sctk-0.20. GUI-only. Missed
      # entirely by the first AI-summarized pass.
      "smithay-clipboard-0.8.0" = "sha256-GojAFRbhJcP0Rpr+v9WOivgW9x38PZdeBWTbMhkDB3A=";
      # pop-os/softbuffer @ tag cosmic-4.0. GUI-only. Missed entirely by
      # the first AI-summarized pass.
      "softbuffer-0.4.1" = "sha256-9Ret/nfieBFl4yJ9TddyWsSuS7sI4QAza/TZrxYMb+I=";
      # pop-os/winit.git @ tag cosmic-0.14 — also covers dpi and the
      # winit-android/-appkit/-common/-core/-orbital/-uikit/-wayland/
      # -web/-win32/-x11 platform-backend crates from the same
      # checkout. GUI-only. Missed entirely by the first AI-summarized
      # pass.
      "winit-0.31.0-beta.2" = "sha256-8r9O5RgVa8vxkPPYvr2aQiRdZ4isg7Jdnk8O5gQIr9k=";
    };
  };

  postPatch = ''
    # buildRustPackage's own consistency check compares the unpacked
    # $src's in-tree Cargo.lock against what cargoLock.lockFile actually
    # vendored — and would fail ("Cargo.lock is not the same in
    # /build/cargo-vendor-dir") since $src still carries the original,
    # un-deduped lockfile. Overwrite it with the same patchedCargoLock
    # content so the two match.
    cp ${patchedCargoLock} Cargo.lock

    # super-stt-app/-consent/-cosmic-applet (the GUI workspace members,
    # never built here — see cargoBuildFlags) are the ONLY reason
    # cargo's resolver ever needs libcosmic/cosmic-panel-config/etc at
    # all: even restricted to `-p super-stt-daemon -p super-stt-cli`,
    # cargo still loads every workspace member's manifest, and one of
    # them (cosmic-panel-config, fetched from a separate repo we can't
    # patch) declares its own `cosmic-config` git dependency via a bare
    # URL with no rev — which our dedupe above can't satisfy, and which
    # fails under --offline trying to re-resolve from the network.
    # Dropping these 3 from the workspace member list means cargo never
    # loads their manifests, so it never walks into that subtree in the
    # first place. Verified 2026-10-25: these 3 names appear nowhere
    # else in Cargo.toml (`grep -n 'super-stt-app\|super-stt-consent\|
    # super-stt-cosmic-applet' Cargo.toml`), only in the members/
    # default-members arrays, so a plain line-delete is safe.
    sed -i \
      -e '/"super-stt-app",/d' \
      -e '/"super-stt-consent",/d' \
      -e '/"super-stt-cosmic-applet",/d' \
      Cargo.toml

    # super-stt-cli-provision.patch's new `provision-model` subcommand
    # needs serde_json directly (it's only available transitively today,
    # via super-stt-shared, which Rust doesn't let a crate `use` by
    # path). dedupe-cargo-lock.py already added the matching entry to
    # Cargo.lock's dependency graph; this is Cargo.toml's side of the
    # same addition.
    sed -i '/clap\.workspace = true/a\    serde_json.workspace = true' super-stt-cli/Cargo.toml
  '';

  # cpal (audio I/O, super-stt-daemon's dependency) links ALSA on Linux.
  # libdbus-sys (keyring/zbus's D-Bus transport) links dbus. enigo (the
  # CLI's --write keyboard-simulation backend) links xkbcommon for
  # keymap handling. All three found incrementally across real build
  # attempts on 2026-10-26 — none of this surfaces until the linker runs.
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [
    alsa-lib
    dbus
    libxkbcommon
  ];

  # The CLI's own binary is literally named super-stt-cli — upstream's
  # docs, install.sh, and `stt record --write` convention all assume a
  # separate installer step (super-stt-install, which we don't build —
  # see the WORKSPACE SUBSET note at the top) renames/symlinks it to
  # `stt`. Since we bypass that installer, nothing else will ever do
  # this for us; without it, `stt` is simply not on PATH after install.
  postInstall = ''
    ln -s $out/bin/super-stt-cli $out/bin/stt
  '';

  meta = {
    description = "Local speech-to-text daemon and CLI (dictation)";
    homepage = "https://github.com/jorge-menjivar/super-stt";
    license = lib.licenses.gpl3Only;
    mainProgram = "super-stt-daemon";
    platforms = lib.platforms.linux;
  };
}
