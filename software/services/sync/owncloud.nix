{ pkgs, ... }:
{
  # ownCloud desktop sync client autostart.
  #
  # This module owns both the client and the autostart entry, and exists to
  # work around a NixOS-specific bug in the client.
  #
  # The client's built-in "Launch on system startup" setting writes
  # ~/.config/autostart/ownCloud.desktop with
  #
  #   Exec=/nix/store/…-owncloud-client-<ver>/bin/.owncloud-wrapped
  #
  # i.e. the *unwrapped* inner binary. Qt derives that path from /proc/self/exe,
  # so it can never see the Nix wrapper. Started that way the client inherits
  # none of the wrapper's Qt environment — no QT_PLUGIN_PATH, no
  # NIXPKGS_QT6_QML_IMPORT_PATH — and aborts at login with a "QML Error" dialog:
  #
  #   module "QtQuick.Controls" plugin "qtquickcontrols2plugin" not found
  #
  # Launching from the app menu works fine, because that uses the packaged
  # owncloud.desktop (Exec=owncloud), which resolves via PATH to the wrapper.
  # The failure is therefore specific to autostart. The hard-coded store path is
  # a second, latent bug: it goes stale after the next garbage collection.
  #
  # Fix: ship our own autostart entry that execs the bare `owncloud` command, so
  # it always goes through the wrapper. It is deliberately named
  # owncloud-client.desktop, NOT ownCloud.desktop, so the client does not
  # recognise it as its own and overwrite it on the next launch.
  #
  # IMPORTANT: the client's own "Launch on system startup" option must be turned
  # OFF in Settings → General, otherwise it rewrites the broken
  # ownCloud.desktop on every start and you get both entries.
  # No extra gating needed: this module is reached only via
  # The client itself. It used to be installed by
  # ../../desktop/productivity/gui-apps.nix — a different bundle — so a host
  # taking services-sync without desktop-productivity got this autostart entry
  # pointing at a binary it had never installed.
  environment.systemPackages = [ pkgs.owncloud-client ];

  environment.etc."xdg/autostart/owncloud-client.desktop".source =
    ../../../dotfiles/autostart/owncloud-client.desktop;
}
