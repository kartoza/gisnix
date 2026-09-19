{ pkgs, pkgs-unstable, ... }:
{
  # Welcome banner is handled by fish interactiveShellInit and the
  # Kartoza branded fastfetch wrapper (see fastfetch.nix)

  # Add system wide packages
  environment.systemPackages = with pkgs; [
    pkgs-unstable.herdr
    asciinema # record your console as ascii movies
    asciinema-agg # record your console as ascii movies
    asciinema-scenario # record your console as ascii movies
    bat # beter implementation of cat
    comma # handy "nix-shell -p" shortcut - just do ", programmename" and it does rather "nix-shell -p programmename"
    fortune # random quotes and sayings
    eza # better ls command
    fd # a modern find implementation
    ffmpeg_6-full # create movies from the command line
    ffmpegthumbnailer # generate video thumbnails
    git # well we all know what this is right?
    gh # github command line tool - see https://cli.github.com/
    gnumake
    gping # a better ping implementation
    imagemagickBig # manipulate images on the command line see e.g. convert command
    kitty # nicer terminal emulator with a lot of cool features
    mdcat # render markdown in your shell
    nixfmt
    nix-direnv # see https://github.com/nix-community/nix-direnv
    nix-prefetch-github # see https://github.com/seppeljordan/nix-prefetch-github
    nix-search-tv # terminal ui for searching nixpkgs
    pgcli # better psql client for postgres
    powertop # swee what apps use the most power on your machine
    poppler-utils # for manipulating PDF files and converting them to other formats.
    restic # for local backups
    rpl # search and replace strings in files
    rsync # file sync
    tailspin # a log file highlighter
    unlock-host # remote ZFS boot-unlock dispatcher for encrypted-root hosts:
    # unlock-host <lan-ip> <initrd-ssh-port> [user] — see hosts/fleet.nix's
    # initrdSshPort field for the port
    t-rec # blazingly fast terminal recorder that saveas as animated gifs
    unzip # unzip stuff
    usbutils # lsusb etc
    wget # fetch files over http
  ];
}
