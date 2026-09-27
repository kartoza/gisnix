{ pkgs, ... }:
{
  # Antigravity (VS Code fork Electron IDE), bubblewrap-sandboxed
  environment.systemPackages = [
    pkgs.antigravity-sandboxed
  ];

  # antigravity (wrapped by antigravity-sandboxed) is Google-proprietary and
  # unfree; allow-list it or a host taking terminal-ai fails to evaluate. Being
  # an Electron app it may also trip the insecure gate on some releases — the
  # all-bundles eval check (utils/check-bundle-eval.sh) will name the exact
  # version string to add to kartoza.insecurePackages if so.
  kartoza.unfreePackages = [ "antigravity" ];
}
