# discourse-tui — not in nixpkgs (checked: no pkgs/by-name/di/discourse-tui,
# nixpkgs master, 2026-09-16). Local derivation until it lands upstream.
#
# All dependencies (ratatui, crossterm, discourse-api-rs, tokio, serde,
# toml, directories, regex) are plain crates.io versions — no git/path
# deps — so cargoLock.lockFile can read the checksums straight out of the
# upstream Cargo.lock rather than needing a separately-guessed cargoHash.
#
# Upstream: https://github.com/ducks/discourse-tui (MIT)
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
}:
rustPlatform.buildRustPackage rec {
  pname = "discourse-tui";
  version = "20260125.0.2";

  src = fetchFromGitHub {
    owner = "ducks";
    repo = "discourse-tui";
    rev = "v${version}";
    # Computed outside Nix (this sandbox has no working nix daemon to
    # build with): downloaded the same GitHub archive tarball
    # fetchFromGitHub would, and hashed it with `nix hash path` — cross-
    # checked against a plain `git clone` of the same tag, which produced
    # an identical hash. Not verified against an actual `nix build`.
    hash = "sha256-Tig0/NzRdFbCmw0HoO6Xac9hXauUf4Gw6gPxPK7oMmg=";
  };

  cargoLock.lockFile = "${src}/Cargo.lock";

  # None of discourse-tui's OWN dependencies (ratatui, crossterm, tokio,
  # serde, toml, directories, regex) need this — it is discourse-api-rs's
  # HTTP client pulling in native-tls -> openssl-sys transitively
  # (confirmed in Cargo.lock; real build failure on abyss: "Could not
  # find directory of OpenSSL installation ... pkg-config could not be
  # found"). Standard nixpkgs recipe for an openssl-sys dependency: give
  # it pkg-config to find the system OpenSSL rather than vendoring one.
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];

  meta = {
    description = "Terminal UI for browsing Discourse forums";
    homepage = "https://github.com/ducks/discourse-tui";
    license = lib.licenses.mit;
    mainProgram = "discourse-tui";
    platforms = lib.platforms.unix;
  };
}
