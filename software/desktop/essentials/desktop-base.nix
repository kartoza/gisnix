# Desktop base — DE-agnostic desktop pieces that are NOT COSMIC-repo
# packages. The bare minimum for a usable COSMIC session — clipboard
# history, document viewers, screen recording, and the rest of what a
# workstation also wants live in the separate desktop-essentials-extras
# bundle instead, so a fast first install can skip them and add them back
# with `gisnix configure` once there's a GUI to do it from.
{
  pkgs,
  lib,
  hostConfig,
  ...
}:
{
  environment.systemPackages = (
    with pkgs;
    [
      # --- Always-on: minimum for a functional COSMIC session ---
      nautilus # File manager (cosmic-files is disabled)
      wl-clipboard # Wayland clipboard
      libnotify # Desktop notifications
      xdg-utils # xdg-open for URL/file opening
      # Screenshot capture tools — also referenced (by store path) by the
      # cosmic screenshot keybind glue in the cosmic module.
      grim
      slurp
      satty
      # wayland-info: dumps the interfaces the compositor advertises. Kept
      # always-on because it is the only way to answer "does cosmic-comp expose
      # zwlr_screencopy_manager_v1?" without guessing — grim, satty, wl-screenrec
      # and wlgif/wf-recorder all depend on that protocol, and when it is absent
      # they fail with bare non-zero exits that name no cause.
      wayland-utils
      # Fonts (COSMIC uses Fira by default)
      fira
      fira-code
      fira-code-symbols
      jetbrains-mono
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
    ]
  );
}
