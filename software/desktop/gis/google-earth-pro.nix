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
}
