# gisnix installer ISO configuration — x86_64 only for now (see
# SPECIFICATION.md / TODO for aarch64).
{
  config,
  lib,
  pkgs,
  modulesPath,
  gisnixInstaller,
  ...
}:
{
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];

  image.baseName = lib.mkForce "gisnix-installer-x86_64";

  isoImage.storeContents = [ ];
  isoImage.squashfsCompression = "zstd -Xcompression-level 19";
  system.includeBuildDependencies = false;

  # The gisnix checkout, baked onto the ISO. Listed explicitly (as tuinix's
  # own installer.nix did) rather than `source = ./.` for the whole
  # directory — a directory copy that isn't careful about it can drag in
  # .git/ and other cruft; naming exactly what a running install needs
  # keeps the ISO's content deliberate. This IS gisnix on the ISO — `kz
  # installer`/`installer` (the package below, on PATH) run straight out of
  # it, and the generated per-machine flake starts by pointing its `gisnix`
  # input here (see installer/installer_run.py) rather than fetching over
  # the network.
  isoImage.contents = [
    {
      source = ./flake.nix;
      target = "/gisnix/flake.nix";
    }
    {
      source = ./flake.lock;
      target = "/gisnix/flake.lock";
    }
    {
      source = ./brand.nix;
      target = "/gisnix/brand.nix";
    }
    {
      source = ./config.nix;
      target = "/gisnix/config.nix";
    }
    {
      source = ./environment.txt;
      target = "/gisnix/environment.txt";
    }
    {
      source = ./installer.nix;
      target = "/gisnix/installer.nix";
    }
    {
      source = ./hosts;
      target = "/gisnix/hosts";
    }
    {
      source = ./users;
      target = "/gisnix/users";
    }
    {
      source = ./profiles;
      target = "/gisnix/profiles";
    }
    {
      source = ./software;
      target = "/gisnix/software";
    }
    {
      source = ./overlays;
      target = "/gisnix/overlays";
    }
    {
      source = ./templates;
      target = "/gisnix/templates";
    }
    {
      source = ./deploy;
      target = "/gisnix/deploy";
    }
    {
      source = ./utils;
      target = "/gisnix/utils";
    }
    {
      source = ./installer;
      target = "/gisnix/installer";
    }
    {
      source = ./resources;
      target = "/gisnix/resources";
    }
    {
      source = ./docs/scripts;
      target = "/gisnix/docs/scripts";
    }
    {
      source = ./tests;
      target = "/gisnix/tests";
    }
    {
      source = ./tests.nix;
      target = "/gisnix/tests.nix";
    }
  ];

  environment.systemPackages = [
    gisnixInstaller
    pkgs.git
    pkgs.vim
    pkgs.curl
  ];

  # SSH: installed for rescue use but NOT started by default — the live ISO
  # has a well-known root password, so exposing sshd unsolicited would let
  # anyone on the LAN log in during installation. To enable rescue access:
  # passwd && systemctl start sshd
  services.openssh.enable = true;
  systemd.services.sshd.wantedBy = lib.mkForce [ ];

  users.users.root = {
    password = "gisnix";
    initialHashedPassword = lib.mkForce null;
    hashedPassword = lib.mkForce null;
    hashedPasswordFile = lib.mkForce null;
    initialPassword = lib.mkForce null;
  };

  networking.networkmanager.enable = true;
  networking.wireless.enable = lib.mkForce false;
  networking.firewall.enable = lib.mkForce false;

  # Enable flakes and nix-command for disko and nixos-install
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # ZFS is x86_64-only in nixpkgs — fine here, this ISO is x86_64-only too.
  boot.supportedFilesystems = [ "zfs" ];

  # Disable everything not needed for a terminal installer
  services.udisks2.enable = lib.mkForce false;
  security.polkit.enable = lib.mkForce false;
  documentation.enable = lib.mkForce false;
  documentation.man.enable = lib.mkForce false;
  documentation.nixos.enable = lib.mkForce false;
  services.xserver.enable = lib.mkForce false;
  services.printing.enable = lib.mkForce false;
  xdg.mime.enable = lib.mkForce false;
  xdg.icons.enable = lib.mkForce false;

  # Symlink /iso/gisnix to /home/gisnix and land there on login, same
  # convention tuinix used (~/tuinix as the "you are already home" cue).
  system.activationScripts.gisnix-home = ''
    mkdir -p /home
    ln -sfn /iso/gisnix /home/gisnix
  '';

  programs.bash.loginShellInit = ''
    if [ -d /home/gisnix ]; then
      cd /home/gisnix
      echo ""
      echo "Welcome to gisnix. Run 'installer' to begin, or 'installer --mock' to preview it safely."
      echo ""
    fi
  '';

  system.stateVersion = "26.05";
}
