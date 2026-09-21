# One unfree-package allow-list, and one insecure-package allow-list, each
# contributed to from anywhere.
#
# THE PROBLEM THIS SOLVES
#
# `nixpkgs.config.allowUnfreePredicate` is a function, and the module system
# merges a function-valued option by picking ONE definition. Nine files in
# this repo defined it — retroarch.nix, five user files, two host files — and
# exactly one of them took effect. The rest were silently discarded, along
# with every package they meant to allow.
#
# The symptom is baffling: a module lists a package in its own predicate,
# right there in the same file, and nix still refuses to evaluate it because
# some other file's predicate won. A host hits this the moment it takes the
# desktop-games bundle: retroarch.nix allows libretro-genesis-plus-gx, but a
# user file's predicate is the one that happens to survive instead.
#
# `nixpkgs.config.permittedInsecurePackages` gets the SAME treatment for the
# same underlying reason, confirmed on a real host taking two bundles that
# each permit a different EOL Electron: `nixpkgs.config` itself is a bare,
# loosely-typed attrs value handed straight to `import nixpkgs { config =
# ...; }` — NixOS never gave permittedInsecurePackages (or
# allowUnfreePredicate) its own properly-declared, list-merging option, so
# two files each setting that one key inside the bare attrs collide exactly
# like the predicate did: gui-apps.nix permits Logseq's electron 39,
# koodo-reader.nix permits its own electron 41, and only one of those two
# lists survives to become the real nixpkgs.config.permittedInsecurePackages
# — koodo-reader's build then refuses with "marked as insecure", on a
# package whose OWN file already tried to permit exactly that version.
#
# THE FIX
#
# A list option instead, same shape as unfreePackages. Lists merge by
# concatenation, so every contributor is kept:
#
#   kartoza.unfreePackages = [ "libretro-genesis-plus-gx" ];
#   kartoza.insecurePackages = [ "electron-41.9.1" ];
#
# Add either anywhere — a module, a user, a host — and it works regardless
# of what else declares packages. Nothing is silently dropped.

{ config, lib, ... }:

let
  cfg = config.kartoza;
in
{
  options.kartoza.unfreePackages = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "google-chrome" ];
    description = ''
      Unfree package names this machine is permitted to build, by
      `lib.getName`. Contributed to from any module; the definitions are
      concatenated rather than one winning.

      Note this is the package NAME, not the attribute path —
      `libretro-genesis-plus-gx`, not `libretro.genesis-plus-gx`. The error
      nix prints when it refuses a package tells you the right string.
    '';
  };

  options.kartoza.insecurePackages = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "electron-41.9.1" ];
    description = ''
      Insecure/EOL package names this machine is permitted to build, by
      `lib.getName`. Same reasoning as `unfreePackages` — contributed to
      from any module, concatenated rather than one winning, because
      `nixpkgs.config.permittedInsecurePackages` set directly has the exact
      same last-definition-wins problem `allowUnfreePredicate` does.

      Use sparingly and say why in the module that sets it: this is for a
      specific, named package version with a known reason it's stuck (an
      app that bundles its own EOL Electron, say), not a general escape
      hatch.
    '';
  };

  config.nixpkgs.config = {
    allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) cfg.unfreePackages;
    permittedInsecurePackages = cfg.insecurePackages;
  };
}
