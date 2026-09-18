{
  # NixOS system.stateVersion — set once at first install, then left alone.
  nixosStateVersion = "26.05";

  # Default admin account created on hosts that import users/example.nix.
  # The installer asks for a real username and email instead of using these.
  adminUser = "admin";
  adminEmail = "admin@example.com";

  # Domain used to build FQDNs (networking.hostName + this).
  domain = "example.com";
}
