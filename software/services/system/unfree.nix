# One unfree-package allow-list, contributed to from anywhere.
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
# some other file's predicate won. abyss hit this the moment it took the
# desktop-games bundle: retroarch.nix allows libretro-genesis-plus-gx, and
# users/tim.nix's predicate was the one that survived.
#
# THE FIX
#
# A list option instead. Lists merge by concatenation, so every contributor is
# kept, and one predicate here consults the union:
#
#   kartoza.unfreePackages = [ "libretro-genesis-plus-gx" ];
#
# Add that anywhere — a module, a user, a host — and it works regardless of
# what else declares packages. Nothing is silently dropped.

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

  config.nixpkgs.config.allowUnfreePredicate =
    pkg: builtins.elem (lib.getName pkg) cfg.unfreePackages;
}
