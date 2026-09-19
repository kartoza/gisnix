# Turn a host's `bundles` list into the modules it imports.
#
# A host says what it wants, in hosts/<name>/config.nix:
#
#   bundles = [ "desktop-browsers" "desktop-productivity" ];
#
# and this imports those bundles' modules, plus anything they imply,
# transitively. See software/bundles.nix for how bundles are discovered and
# docs/references/bundles.md for what each one contains.
#
# WHY THIS IS A SEPARATE PROFILE
#
# `imports` cannot depend on `config`, because the module system has to know
# the full set of modules before it can evaluate any option. hostConfig is
# passed through specialArgs precisely so it is available at that point — it
# is a plain attrset read from a file, not a NixOS option — which is what
# makes this possible at all.
#
# A host with no `bundles` key gets nothing from here and keeps importing its
# software the old way. That is deliberate: it lets hosts migrate one at a
# time, with each one's package set checked against the last, rather than all
# nine moving at once on the strength of an assertion that nothing changed.

{ lib, hostConfig, ... }:

let
  bundles = import ../software/bundles.nix { inherit lib; };

  wanted = hostConfig.bundles or [ ];

  # Bundles marked selection = "one-of" hold alternatives, not a set, so they
  # contribute nothing automatically — a machine has one locale, not eight,
  # and one kernel, not two. The host names the member it wants with the
  # bundle's own `choiceKey`:
  #
  #   locale = "pt-en";   ->  software/locale/locale-pt-en.nix
  #   kernel = "latest";  ->  software/base/kernel/kernel-latest.nix
  #
  # Driven off the registry rather than a list here: adding a third choice
  # group is then a bundle.json and two modules, with nothing to remember to
  # wire up. A host naming no value for a group simply imports none of its
  # members, which for `kernel` is exactly right — no module means the NixOS
  # default kernel, which is what "stable" is.
  #
  # A one-of group WITHOUT a `choiceKey` is not driven by a host key and is
  # skipped here. No group is in that state today — boot-themes was, chosen
  # by importing a profile, and is now `bootTheme` like any other — but
  # assuming every group had a key is what broke a host's rebuild with
  # `attribute 'choiceKey' missing` the day boot-themes still worked that
  # way, so the guard stays. check-bundles.py refuses a group declaring
  # neither a key nor how else it is chosen.
  chosen = lib.concatMap (
    b:
    let
      key = b.choiceKey or null;
      prefix = b.modulePrefix or key;
      value = if key == null then null else hostConfig.${key} or null;
    in
    lib.optional (value != null) (../software + "/${b.path}/${prefix}-${value}.nix")
  ) (lib.attrValues bundles.choices);
in
{
  imports = bundles.importsFor wanted ++ chosen;
}
