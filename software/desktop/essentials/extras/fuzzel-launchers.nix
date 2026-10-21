# fuzzel-powered launcher panels — one shared, tasteful theme (fuzzel.ini:
# a dark, rounded, generously-padded look, not tied to any one brand) that
# every launcher bound here inherits, same as herdr.nix/kitty.nix's
# single-source-of-truth dotfile pattern.
#
# COSMIC has no NixOS-declarative custom-shortcut mechanism gisnix can hook
# into (see docs/user/post-install.md's own "Custom keyboard shortcuts"
# section) — every command below is a binary on PATH, bound by hand via
# Settings → Input devices → Keyboard shortcuts → Custom shortcuts.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    fuzzel

    # Emoji/unicode picker, through fuzzel: fuzzy-filter as you type, same
    # as any other fuzzel menu. `--action copy` rather than `type` — typing
    # needs a Wayland virtual-keyboard-protocol tool (wtype/ydotool), which
    # cosmic-comp's protocol support is inconsistent about (the same class
    # of gap that broke wf-recorder's screencopy path — see wlgif's own
    # comment in desktop-base-extras.nix); wl-copy only needs the
    # clipboard protocol, which works everywhere. Paste with Ctrl+V after
    # picking.
    #
    #   Super+E → emoji-picker   (bind by hand, see module comment above)
    (writeShellApplication {
      name = "emoji-picker";
      runtimeInputs = [
        rofimoji
        fuzzel
        wl-clipboard
      ];
      text = ''
        exec rofimoji --selector fuzzel --action copy
      '';
    })

    # Every keybind table in docs/user/keyboard.md, in one fuzzy-searchable
    # panel — parses the actual markdown (keybind-cheatsheet.py), rather
    # than a second, hand-maintained copy of the same bindings that could
    # drift from it. Covers what gisnix itself documents there (home-row
    # mods, bracket chords, clipboard holds, nav layer, herdr layer) —
    # aerc/obs and anything else private has no table in gisnix's own
    # docs to parse, but shows up too if a host drops its own markdown
    # fragment, same table shape, into /etc/xdg/keybind-cheatsheet/*.md.
    #
    #   Super+K → keybind-cheatsheet   (bind by hand, see module comment above)
    (writeShellApplication {
      name = "keybind-cheatsheet";
      runtimeInputs = [
        python3
        fuzzel
      ];
      text = ''
        exec python3 ${./keybind-cheatsheet.py} ${../../../../docs/user/keyboard.md} "$@"
      '';
    })
  ];

  environment.etc."xdg/fuzzel/fuzzel.ini" = {
    mode = "0444";
    source = ./fuzzel.ini;
  };

  system.activationScripts.fuzzelConfig = ''
    for dir in /home/*; do
      user="$(basename "$dir")"
      if id "$user" &>/dev/null && [ -d "$dir" ]; then
        mkdir -p "$dir/.config/fuzzel"
        ln -sf /etc/xdg/fuzzel/fuzzel.ini "$dir/.config/fuzzel/fuzzel.ini"
        chown -h "$user":"$(id -gn "$user")" \
          "$dir/.config/fuzzel" \
          "$dir/.config/fuzzel/fuzzel.ini" 2>/dev/null || true
      fi
    done
  '';
}
