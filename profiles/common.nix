{
  config,
  lib,
  pkgs,
  projectConfig,
  ...
}:
{
  imports = [
    # Memory-pressure guard, fleet-wide. Every host here has
    # swapDevices = [ ], so there is no cushion when something allocates hard.
    # The other half of that guard — capping the ZFS ARC, which OpenZFS
    # otherwise lets grow to all-but-1GiB — is now a declared option set per
    # host in its hardware.nix; see software/base/zfs.nix.
    ../software/base/zram.nix
    # /etc/hosts entries for the whole fleet, generated from hosts/fleet.nix
    # so every machine can reach every other by name whether or not the
    # overlay network is up. Replaces nine hand-maintained copies.
    ../software/services/system/fleet-hosts.nix
    # One unfree allow-list, contributed to from anywhere. Nine files used to
    # define nixpkgs.config.allowUnfreePredicate and exactly one took effect,
    # because the module system merges a function-valued option by picking a
    # single definition. See that file for the full story.
    ../software/services/system/unfree.nix
  ];

  # Enable QEMU binfmt emulation for cross-architecture builds.
  # This allows building aarch64 and armv7l packages on x86_64.
  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
    "armv7l-linux"
  ];

  # Secrets
  age.identityPaths = [ "/root/.agenix/agenix.key" ];

  # Security
  # NOTE: wheelNeedsPassword = false is intentional for development convenience
  # on workstations where users are trusted. For production servers, consider
  # setting this to true or using more restrictive sudo rules.
  security.sudo = {
    enable = true;
    execWheelOnly = true;
    wheelNeedsPassword = false;
  };

  # Increase file descriptor limits for builds (needed for niri tests, etc.)
  # See: https://github.com/sodiboo/niri-flake/issues/1300
  # Per-country wireless channel and TX-power limits. Previously arrived via
  # software/system/wifi-audit.nix; kept when that module was dropped because
  # it governs ordinary wifi behaviour, not auditing, and matters on laptops
  # that change regulatory domain.
  hardware.wirelessRegulatoryDatabase = true;

  security.pam.loginLimits = [
    {
      domain = "*";
      type = "soft";
      item = "nofile";
      value = "4096";
    }
    {
      domain = "*";
      type = "hard";
      item = "nofile";
      value = "1048576";
    }
  ];

  # Nix
  nix.settings = {
    trusted-users = [ "@wheel" ];

    # Binary caches for faster builds
    substituters = [
      "https://cache.nixos.org/"
      "https://nix-community.cachix.org"
      "https://cosmic.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cosmic.cachix.org-1:Dya9IyXD4xdBehWjrkPv6rtxpmMdRel02smYzA85dPE="

      # Operator build keys go here. `kz update <host>` builds a closure
      # locally and signs it (utils/update.sh) before copying it over;
      # without the signing key listed here, that signature satisfies nobody
      # and the copy can only work because the deploying user happens to be
      # in trusted-users on the receiving host — a single point of failure
      # with no fallback.
      #
      # These are PUBLIC keys — safe to commit, and useless without the
      # matching secret in the operator's ~/.config/nix/. Add a line per
      # operator machine; the key is printed on first use and lives in
      # ~/.config/nix/local-build-key.pub.
    ];

    # Build optimization - use all cores except 2 for system responsiveness
    # max-jobs = "auto" lets Nix decide based on available resources
    # cores can be overridden per-host if needed
    max-jobs = "auto";
    cores = lib.mkDefault 0; # 0 = use all cores; override per-host for cores-2

    # Keep build dependencies and outputs for faster rebuilds
    keep-outputs = true;
    keep-derivations = true;

    # Enable auto-optimization
    auto-optimise-store = true;

    # Faster builds with less logging
    log-lines = 25;

    # Use more build users for parallel builds
    build-users-group = "nixbld";

    # Allow building for emulated architectures (via binfmt)
    # This tells nix it can build for these platforms using QEMU emulation
    extra-platforms = [
      "aarch64-linux"
      "armv7l-linux"
    ];

    # System features required for ARM emulation builds
    # gccarch-armv7-a is needed for armv7l bootstrap toolchain
    system-features = [
      "benchmark"
      "big-parallel"
      "kvm"
      "nixos-test"
      "gccarch-armv7-a"
    ];
  };

  # Nix Flakes
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # Other
  documentation.nixos.enable = false;

  # System
  system.configurationRevision = projectConfig.configRevision;
  system.stateVersion = projectConfig.nixosStateVersion;
}
