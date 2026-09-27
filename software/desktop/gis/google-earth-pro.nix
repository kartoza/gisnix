{
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    googleearth-pro
  ];

  # googleearth-pro is unfree, so it must be named in the allow-list or the
  # host fails to EVALUATE ("has an unfree license, refusing to evaluate") —
  # which is what broke a bare-metal install that took this bundle. The string
  # is `lib.getName`'s value for the package (its pname); it is added here,
  # beside the package, so the two never drift. See
  # software/services/system/unfree.nix for how the list is merged.
  kartoza.unfreePackages = [ "googleearth-pro" ];

  # googleearth-pro ALSO bundles a component nixpkgs marks INSECURE, so it must
  # be permitted by its exact name+version too — otherwise the host still
  # refuses to evaluate ("googleearth-pro-<version> is marked as insecure").
  # This is version-pinned by design: when nixpkgs bumps googleearth-pro, this
  # string must be updated to match, which is the prompt to re-read the
  # advisory rather than permit it blindly. See unfree.nix (insecurePackages).
  kartoza.insecurePackages = [ "googleearth-pro-7.3.7.1155" ];
}
