{
  hostname,
  ...
}:
{
  # COSMIC desktop — System76's Rust/Wayland desktop environment.
  #
  # This profile now does one thing: say that this host runs COSMIC, and pull
  # in the host's own desktop file. Everything else it used to import — the
  # terminal collection, the desktop applications, the heavy system services —
  # is declared by each host as bundles in its config.nix.
  #
  # That is the point of the bundle work. Those three imports were flat
  # aggregators spanning five categories each, so a host's config.nix could
  # not tell you what the machine installed: ten bundles arrived here,
  # invisibly, and no host named any of them. Now the host's list is the
  # answer.
  imports = [
    ../hosts/${hostname}/desktop.nix
  ];

  # Enable the Kartoza COSMIC configuration (compositor settings, greeter,
  # wallpaper, panel layout — see software/desktop/environments/cosmic).
  kartoza.cosmic = {
    enable = true;
    wallpaper = ../resources/kartoza-wallpaper.png;
  };
}
