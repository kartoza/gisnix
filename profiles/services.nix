{
  config,
  pkgs,
  projectConfig,
  hostname,
  ...
}:

{
  imports = [
    ../software/services/system/ssh.nix
    # Defines kartoza.ssh.restrictToTrustedNetworks. Imported everywhere so
    # the option exists on every host; it does nothing until a host sets it.
    ../software/services/system/ssh-access.nix
    ../software/services/system/harden.nix
    ../software/services/system/ca-certificates.nix
    # DNS filtering, fleet-wide. Previously imported by four hosts out of
    # nine, which meant whether a user was exposed to ad and tracker domains
    # depended on which machine they happened to be issued. Blocky listens on
    # 127.0.0.1 only and never serves the network, so this is safe to apply
    # everywhere. `nix run .#dns-off` pauses it temporarily when a developer
    # needs to reproduce what an unfiltered user sees.
    ../software/services/dns/blocky.nix
    ../software/services/dns/block-doh.nix
    # Any host specific configuration goes in the host folders services.nix
    ../hosts/${hostname}/services.nix
  ];
}
