{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [ ./kartoza-webapps ];

  # Enable every web app this module ships. Each is a Chromium app-mode
  # launcher with its own profile, launcher entry and panel icon.
  #
  # To add one: drop an icon in kartoza-webapps/assets/ and add a five-line
  # entry to `apps` in kartoza-webapps/default.nix. The nuances that make the
  # panel icon actually attach — the app_id-derived desktop filename, the icon
  # namespacing, and why NoDisplay must never be set — are written up in
  # kartoza-webapps/README.md. Read it before changing the machinery.
  #
  # A downstream flake with its own private web apps (an internal ERP, a
  # private Sentry/monitoring instance) adds its own equivalent module
  # rather than extending this one — programs.kartoza-webapps.apps'
  # schema is generated from THIS file's own app list, so another module
  # can only toggle .enable on an app already defined here, not add a new
  # one under a name of its own.
  programs.kartoza-webapps.enableAll = true;
}
