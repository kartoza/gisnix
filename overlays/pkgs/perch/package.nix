# perch — terminal social client for Mastodon and Bluesky. Not in nixpkgs
# (checked: no pkgs/by-name/pe/perch, nixpkgs master, 2026-09-16).
#
# GPL-3.0-or-later — approved by Tim 2026-09-16 (the fleet's dependency
# policy blocks GPL/AGPL unless explicitly approved; see the commit this
# shipped in for the rest of that conversation).
#
# Every dependency is a plain crates.io version — no git/path deps — so
# cargoLock.lockFile reads checksums straight out of upstream's own
# Cargo.lock, same as discourse-tui.
#
# Upstream: https://github.com/ricardodantas/perch
{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
rustPlatform.buildRustPackage rec {
  pname = "perch";
  version = "0.3.4";

  src = fetchFromGitHub {
    owner = "ricardodantas";
    repo = "perch";
    rev = "v${version}";
    # Computed outside Nix (no working nix daemon here to build with):
    # downloaded the GitHub archive tarball fetchFromGitHub would fetch
    # and hashed it with `nix hash path`. Not verified against an actual
    # `nix build` — see discourse-tui/package.nix for the cross-check
    # that gives confidence in this method.
    hash = "sha256-TURpPI4Nj9xfTUEY90KCDgrGFjXGm+/n3cVxxOM709k=";
  };

  cargoLock.lockFile = "${src}/Cargo.lock";

  meta = {
    description = "Terminal social client for Mastodon and Bluesky";
    homepage = "https://github.com/ricardodantas/perch";
    license = lib.licenses.gpl3Plus;
    mainProgram = "perch";
    platforms = lib.platforms.unix;
  };
}
