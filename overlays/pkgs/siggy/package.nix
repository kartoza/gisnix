# siggy — terminal Signal messenger client. Not in nixpkgs (checked: no
# pkgs/by-name/si/siggy, nixpkgs master, 2026-09-16).
#
# AGPL-3.0-only — approved by Tim 2026-09-16 (the fleet's dependency
# policy blocks GPL/AGPL unless explicitly approved; see the commit this
# shipped in for the rest of that conversation).
#
# ARCHITECTURE: siggy does not reimplement the Signal protocol. It wraps
# signal-cli (also packaged in nixpkgs, added alongside this in chat.nix)
# via JSON-RPC — the standard, safer way unofficial clients talk to
# Signal. First launch runs a setup wizard that locates signal-cli,
# takes your phone number, and links this as a secondary device via QR
# code, same flow as Signal Desktop. Signal has a documented history of
# pushing back on unofficial clients; nothing here changes that risk,
# it is simply talking to Signal exactly the way signal-cli itself does.
#
# BUILD FEATURES: siggy also HAS a from-scratch "native-backend" that
# talks to Signal's servers directly via the presage crate, mutually
# exclusive with signal-cli-backend by design (upstream: compiling both
# together is a build error). signal-cli-backend is upstream's own
# default, and the only one we want — pinned explicitly below so a
# future upstream default change can't silently switch us onto the
# from-scratch protocol implementation.
#
# GIT DEPENDENCIES: native-backend's dependency chain (presage and its
# forked libsignal/curve25519-dalek/spqr) still has to be VENDORED even
# though it is never compiled — `cargo vendor`/importCargoLock fetch
# every source Cargo.lock names, regardless of which features end up
# built. Hence the five outputHashes below, one per unique git checkout
# (nixpkgs keys outputHashes by one representative "name-version" per
# checkout — see import-cargo-lock.nix — so e.g. libsignal's NINE
# co-located crates — account-keys, core, debug, protocol, poksho,
# signal-crypto, usernames, zkcredential, zkgroup — share the one
# "libsignal-core-0.1.0" entry).
#
# The first version of this list was built from an AI-summarized fetch
# of the lockfile rather than the raw file, and silently dropped four
# libsignal crates (harmless — already covered by the same checkout) AND
# the entire fifth repo, spqr (signalapp/SparsePostQuantumRatchet) —
# not harmless: the real build failed on it with "No hash was found
# while vendoring the git dependency spqr-1.5.1". This list is now
# built from grep against the actual Cargo.lock text — see the commit
# that added this paragraph for the exact command.
#
# Upstream: https://github.com/johnsideserf/siggy
{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
rustPlatform.buildRustPackage rec {
  pname = "siggy";
  version = "1.15.0";

  src = fetchFromGitHub {
    owner = "johnsideserf";
    repo = "siggy";
    rev = "v${version}";
    # Computed outside Nix (no working nix daemon here to build with):
    # downloaded the GitHub archive tarball fetchFromGitHub would fetch
    # and hashed it with `nix hash path`. Cross-checked once against a
    # plain `git clone` of the same tag — see discourse-tui/package.nix
    # — which is the basis for trusting this method; it is what caught
    # every hash below EXCEPT the source hash actually needed a real
    # `nixos-rebuild` to expose the missing outputHashes entry (this
    # method computes a hash correctly once it is told what to hash —
    # it cannot discover a git dependency the lockfile summary omitted).
    # The five outputHashes below were computed the same way, against a
    # plain checkout of each git dependency at its pinned commit (none
    # declare submodules, checked directly against each repo at that
    # commit — so a plain clone is the same tree fetchgit would produce).
    hash = "sha256-A4MP5KueSASifhN4q1S6wkIi2ceJFwX8wJjnxiSiMk4=";
  };

  buildNoDefaultFeatures = true;
  buildFeatures = [ "signal-cli-backend" ];

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
    outputHashes = {
      # signalapp/curve25519-dalek @ signal-curve25519-4.1.3 — also
      # covers curve25519-dalek-derive, same checkout.
      "curve25519-dalek-4.1.3" = "sha256-bPh7eEgcZnq9C3wmSnnYv0C4aAP+7pnwk9Io29GrI4A=";
      # signalapp/libsignal @ v0.94.4 — also covers
      # libsignal-account-keys, libsignal-debug, libsignal-protocol,
      # poksho, same checkout.
      "libsignal-core-0.1.0" = "sha256-Uh/j8cXUWgWgSo9UBfYOFuC8i+2YdMwGHcXf55PkGgU=";
      # whisperfish/libsignal-service-rs (its own repo, one crate).
      "libsignal-service-0.1.0" = "sha256-jH8fk8IbTT9zjCC1eM0UCg/0k+Gdb02iC99RMMN56V4=";
      # whisperfish/presage — also covers presage-store-sqlite, same
      # checkout.
      "presage-0.8.0-dev" = "sha256-9Y6n6fM2TyrCwqxziLKMdVQHHTtU0q3+sJF6/ORTY8M=";
      # signalapp/SparsePostQuantumRatchet @ v1.5.1 — its own repo, one
      # crate. Missing from the first version of this file; see the
      # header comment.
      "spqr-1.5.1" = "sha256-XlqyjWQ5/F25/FdRTc4RDCqp8Gr1LCEBLeatXKnVciI=";
    };
  };

  meta = {
    description = "Terminal Signal messenger client, wrapping signal-cli";
    homepage = "https://github.com/johnsideserf/siggy";
    license = lib.licenses.agpl3Only;
    mainProgram = "siggy";
    platforms = lib.platforms.unix;
  };
}
