# Kanata Keyboard Configuration
#
# Features:
# - Home row mods with bilateral combinations enforcement (GACS layout)
#   Left hand:  a=Super, s=Alt, d=Ctrl, f=Shift
#   Right hand: j=Shift, k=Ctrl, l=Alt, ;=Super
# - Space/menu hold → Navigation/Mouse layer (ESDF home position):
#   - hjkl → arrow keys
#   - esdf → mouse movement
#   - w → left click, r → right click
#   - t → scroll up, g → scroll down
#
{
  config,
  pkgs,
  lib,
  hostConfig,
  ...
}:
# Note: Add your user to the uinput group in your host config:
#   users.groups.uinput.members = [ "your-username" ];
let
  # Timing configuration (in milliseconds)
  # Increased from 200/200 to reduce missed taps and accidental holds
  # - tapTimeout: time window to detect tap vs hold (higher = more forgiving taps)
  # - holdTimeout: delay before hold action activates (higher = slower modifier activation)
  tapTimeout = 280;
  holdTimeout = 280;

  # Which xkb layout this host's keyboards type under — a host knob
  # (`kanataLayout` in hosts/<host>/config.nix, like `email` before it was
  # retired) because the module is shared: abyss and porto type pt-PT,
  # atoll's laptop types US. Layout and chord file are TWO STATEMENTS OF ONE
  # FACT (the chord outputs are keycodes for that layout), so they are
  # selected together here — an unlisted layout fails evaluation rather than
  # pairing a guessed chord file with it.
  layout = hostConfig.kanataLayout or "pt";
  chordsFile =
    {
      pt = ../../../../dotfiles/kanata/chords.kbd;
      us = ../../../../dotfiles/kanata/chords-us.kbd;
    }
    .${layout};
in
{
  # Enable uinput for virtual keyboard/mouse device creation
  hardware.uinput.enable = true;

  # Passwordless sudo for kanata service control (for toggle hotkey)
  security.sudo.extraRules = [
    {
      groups = [ "wheel" ];
      commands = [
        # Wildcard: hosts may run several kanata instances (one per keyboard)
        {
          command = "/run/current-system/sw/bin/systemctl start kanata-*";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl stop kanata-*";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/systemctl restart kanata-*";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # Kanata service configuration
  services.kanata = {
    enable = true;
    keyboards = {
      keyboard = {
        # Match all keyboards
        devices = [ ];

        # Extra defcfg options (concurrent-tap-hold is required by
        # defchordsv2; danger-enable-cmd arms the ONE cmd action in the
        # config — the herdr layer's email key runs kanata-type-email via
        # cmd-output-keys, and kanata refuses cmd actions without this
        # opt-in. The overlay pins kanata-with-cmd so the binary can honour
        # it; the only command any generated config names is that
        # store-pathed script.)
        extraDefCfg = ''
          process-unmapped-keys yes
          concurrent-tap-hold yes
          danger-enable-cmd yes
        '';

        # Kanata configuration (shared base + the chord set matching the
        # host's `kanataLayout` — see the let-binding above). The Glove80
        # runs a SEPARATE instance with its own chords (US layout, its own
        # trigger pairs) — see hosts/abyss/kanata-keyboard.nix and
        # ./kanata-config.nix.
        config = import ./kanata-config.nix {
          inherit
            tapTimeout
            holdTimeout
            layout
            chordsFile
            ;
          expansionsFile = ../../../../dotfiles/kanata/expansions.kbd;
          # Caps Lock is the trigger on a full-size board: holding it is
          # otherwise wasted, so unlike the Glove80's Backspace this costs
          # nothing. A tap still toggles caps.
          herdrKey = "caps";
          clipboardHolds = true;
          # herdr layer `e` types the LOGGED-IN user's address, resolved at
          # press time — this module is porto's and atoll's too, and even on
          # one machine tim and michelle sign differently. The script does
          # its own per-layout keycode selection, hence `layout` riding
          # along inside kanata-config.nix.
          emailScript = "${pkgs.kanata-type-email}/bin/kanata-type-email";
        };
      };
    };
  };

  # Restart a crashed instance. Upstream's kanata module sets no `Restart=`
  # at all, so systemd's default (Restart=no) applies and a crash is
  # terminal: the keyboard silently reverts to its raw layout — no home-row
  # mods, no nav layer — and stays that way until someone notices and
  # restarts by hand. abyss hit exactly that on 2026-08-31, when
  # kanata-keyboard panicked ("Invalid KeyCode: 883") after 30 hours up.
  #
  # A panic like that is transient, so restarting is the right response. It
  # cannot mask a broken config either: the module check-builds every config
  # it generates, so a unit that starts at all has a valid one. The start
  # limit is the backstop for a genuinely unstartable instance — five
  # attempts in a minute, then systemd gives up rather than spinning.
  #
  # Applied to every declared keyboard, so hosts adding an instance (abyss
  # has a second one for the Glove80) get it without repeating themselves.
  systemd.services = lib.mapAttrs' (
    name: _:
    lib.nameValuePair "kanata-${name}" {
      startLimitIntervalSec = 60;
      startLimitBurst = 5;
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = 3;
      };
    }
  ) config.services.kanata.keyboards;

  environment.systemPackages = with pkgs; [
    kanata

    # Toggle script for kanata — enables/disables ALL kanata instances
    # (there may be several, e.g. one per physical keyboard)
    (writeShellScriptBin "kanata-toggle" ''
      #!/usr/bin/env bash
      mapfile -t SERVICES < <(systemctl list-units --all --plain --no-legend 'kanata-*.service' | awk '{print $1}')
      [ ''${#SERVICES[@]} -eq 0 ] && { echo "No kanata services found"; exit 1; }

      if systemctl is-active --quiet "''${SERVICES[0]}"; then
        for s in "''${SERVICES[@]}"; do sudo systemctl stop "$s"; done
        # Raw keyboard = rainbow: unmistakable "remapping is off" signal
        # (no-op on hosts without the Razer lighting stack)
        command -v razer-layer-lights >/dev/null && razer-layer-lights --clear >/dev/null 2>&1 || true
        notify-send -u normal -t 2000 "Kanata" "Keyboard remapping DISABLED" -i input-keyboard
        echo "Kanata disabled (''${SERVICES[*]})"
      else
        for s in "''${SERVICES[@]}"; do sudo systemctl start "$s"; done
        # Repaint immediately; the layer-lights listener also repaints on
        # reconnect (~2 s) as a fallback
        command -v razer-layer-lights >/dev/null && razer-layer-lights >/dev/null 2>&1 || true
        notify-send -u normal -t 2000 "Kanata" "Keyboard remapping ENABLED" -i input-keyboard
        echo "Kanata enabled (''${SERVICES[*]})"
      fi
    '')

    # Status check script
    (writeShellScriptBin "kanata-status" ''
      #!/usr/bin/env bash
      systemctl list-units --all --plain --no-legend 'kanata-*.service' | awk '{print $1, $3}'
    '')

    # Debugging script for kanata
    (writeShellScriptBin "kanata-debug" ''
      #!/usr/bin/env bash
      echo "=== Kanata Keyboard Debugging ==="
      echo "1. Kanata service status:"
      systemctl status kanata-keyboard --no-pager

      echo -e "\n2. Available input devices:"
      ls -la /dev/input/by-path/ | grep -i kbd || echo "No keyboard devices found"

      echo -e "\n3. Kanata logs (last 20 lines):"
      journalctl -u kanata-keyboard --no-pager -n 20

      echo -e "\n4. uinput device:"
      ls -la /dev/uinput 2>/dev/null || echo "/dev/uinput not found"

      echo -e "\n5. Groups for current user:"
      groups
    '')

    (writeShellScriptBin "kanata-test" ''
      #!/usr/bin/env bash
      echo "Testing kanata with verbose output (Ctrl+C to exit)..."
      sudo kanata --cfg /etc/kanata/keyboard.kbd --debug
    '')
  ];
}
