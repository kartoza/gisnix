# ─────────────────────────────────────────────────────────────────────────
# THE BUNDLE SYSTEM
#
# A bundle is a directory under software/. That is the whole idea: the
# taxonomy and the package sets are one system, not two kept in step by hand.
#
#   software/desktop/browsers/
#     bundle.json      what it is, what it needs, what is in it
#     browsers.nix     the module
#
# A host says which bundles it wants, in hosts/<name>/config.nix:
#
#   bundles = [ "desktop-browsers" "desktop-productivity" ];
#
# and gets those plus anything they imply, transitively. A bundle's name is
# its path with slashes turned into hyphens, so the name always says where to
# look for it.
#
# WHY bundle.json LISTS ITS MODULES
#
# "Every .nix in the directory" would be simpler, and wrong. software/desktop/
# gis/ carries several QGIS channels that are alternatives, not companions,
# and the tree holds two dozen modules nothing imports at all. Importing a
# directory wholesale would install every QGIS channel at once and resurrect
# the dead ones.
#
# So membership is explicit, and anything in a directory that no bundle claims
# is listed under "unclaimed" — visible rather than silently dropped.
# utils/check-bundles.py fails when a module is neither claimed nor unclaimed,
# which is what stops a newly added module from quietly never being installed.
#
# WHAT IS NOT A BUNDLE
#
# Bundles are software. Branding, theming and boot appearance stay in
# profiles/. Mixing the two is exactly what turned software/desktop/
# default.nix into a flat list of twenty imports spanning five categories
# that nobody could take apart.
# ─────────────────────────────────────────────────────────────────────────

{ lib }:

let
  root = ./.;

  # Walk software/ and collect every directory carrying a bundle.json.
  # Discovered rather than listed: a registry naming each bundle would be a
  # second source of truth, and the first thing to drift.
  discover =
    dir:
    let
      entries = builtins.readDir dir;
      subdirs = lib.filterAttrs (_: t: t == "directory") entries;

      here =
        if builtins.pathExists (dir + "/bundle.json") then
          let
            meta = builtins.fromJSON (builtins.readFile (dir + "/bundle.json"));
          in
          [
            (
              meta
              // {
                # Absolute paths, ready to hand straight to `imports`.
                modulePaths = map (m: dir + "/${m}") meta.modules;
              }
            )
          ]
        else
          [ ];

      deeper = lib.concatMap (name: discover (dir + "/${name}")) (builtins.attrNames subdirs);
    in
    here ++ deeper;

  found = discover root;

  byName = builtins.listToAttrs (map (b: lib.nameValuePair b.name b) found);

  # Resolve `implies` transitively. A host asking for desktop-browsers gets
  # the desktop needed to display them without having to know that it does.
  resolve =
    names:
    let
      step =
        acc: name:
        if builtins.elem name acc then
          acc
        else
          let
            bundle =
              byName.${name} or (throw ''
                Unknown bundle "${name}".

                Bundles are directories under software/ carrying a bundle.json.
                Known bundles:
                  ${builtins.concatStringsSep "\n  " (builtins.attrNames byName)}
              '');
          in
          builtins.foldl' step (acc ++ [ name ]) (bundle.implies or [ ]);
    in
    builtins.foldl' step [ ] names;
in
{
  inherit byName resolve;

  all = found;

  names = builtins.attrNames byName;

  # The imports a host gets for a list of bundle names, implications included.
  #
  # A bundle marked `selection = "one-of"` contributes nothing here: its
  # modules are alternatives, not companions. software/locale/ is the clear
  # case — a machine has one locale, not eight — so the host names the member
  # it wants rather than taking the group.
  importsFor =
    names:
    lib.concatMap (
      n:
      let
        b = byName.${n};
      in
      if (b.selection or "all") == "one-of" then [ ] else b.modulePaths
    ) (resolve names);

  # Bundles whose members are alternatives, for anything that needs to present
  # them as a choice rather than a set.
  choices = lib.filterAttrs (_: b: (b.selection or "all") == "one-of") byName;

  # Everything a directory holds that no bundle claims. Reported by
  # utils/check-bundles.py rather than silently ignored.
  unclaimed = lib.concatMap (b: map (m: "${b.path}/${m}") (b.unclaimed or [ ])) found;
}
