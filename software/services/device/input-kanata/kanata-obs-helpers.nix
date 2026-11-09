# Shared helpers for wiring a kanata instance's herdr/aerc/obs mode-cycle
# (kanata-config.nix's dualMode): the sound-player wrapper for the
# mode-toggle beep, and obsLayer's own scene-step script + brand prefix.
# Factored out of kanata-keyboard.nix so a HOST running a SECOND kanata
# instance (abyss's Glove80, alongside the main one) can wire the same
# obsLayer/aercLayer behaviour into it without duplicating either script —
# duplicating obs-scene-step in particular would risk the two copies
# drifting out of lockstep with obs-setup.py's own scene order.
{ pkgs, hostConfig }:
let
  # obsLayer's scene-switch bindings need the same brand prefix
  # obs-setup.py namespaced the scenes with ("Kartoza Webcam", "QGIS
  # Webcam") — this is the SAME hostConfig.bootTheme ternary
  # obs-scenes.nix uses for the same reason; if you change one, change the
  # other, or a host's keyboard starts switching to scenes that don't
  # exist in its own OBS.
  obsScenePrefix = if (hostConfig.bootTheme or "kartoza") == "qgis" then "QGIS" else "Kartoza";

  # kanata's own systemd unit is a SYSTEM service (it needs /dev/uinput and
  # /dev/input, which is also why it carries the uinput/openrazer
  # supplementary groups below) — not something the user's session manager
  # spawned. Systemd only sets XDG_RUNTIME_DIR for units IT launches inside
  # a user's own manager; a bare `pw-play` invoked from this service's
  # `cmd` actions (the herdr<->aerc mode-toggle beep, herdr's macro-record
  # click) has no PipeWire socket to reach and fails silently — the `cmd`
  # "succeeds" from kanata's point of view
  # (pw-play exits nonzero, kanata just logs it), so nothing looked broken
  # short of actually listening for the sound. This wrapper hunts down
  # whichever logged-in user's PipeWire socket is actually up and plays
  # into that one, rather than hardcoding a uid that would break the
  # moment a different user logs in or the uid changes.
  kanataPlaySound = pkgs.writeShellScriptBin "kanata-play-sound" ''
    for sock in /run/user/*/pipewire-0; do
      if [ -S "$sock" ]; then
        export XDG_RUNTIME_DIR="''${sock%/pipewire-0}"
        exec ${pkgs.pipewire}/bin/pw-play "$@"
      fi
    done
    # No PipeWire session up — nothing to play into. Exit 0 regardless:
    # a `cmd` action failing is not a reason to disrupt the key press it
    # rode in on.
    exit 0
  '';

  # j/k on the obs layer — steps the program scene forward/backward
  # through gisnix's OWN 8-scene order (obs-setup.py's SCENE_BASE_NAMES:
  # Intro, Webcam, Screen, ScreenCam, ScreenOverlay, Terminal, Outro,
  # BRB — keep this bash array and that Python list in lockstep, not
  # whatever order obs-websocket's GetSceneList happens to report — that
  # depends on OBS's own scene-insertion behaviour, which this has no
  # business depending on. Pure network I/O (obs-websocket over
  # localhost), so — unlike kanataLayerIndicator's Wayland/GTK problem —
  # kanata's locked-down DynamicUser service has everything it needs to
  # run this directly, no session access required.
  obsSceneStep = pkgs.writeShellApplication {
    name = "obs-scene-step";
    runtimeInputs = [ pkgs.obs-cli ];
    text = ''
      direction="$1"
      order=(Intro Webcam Screen ScreenCam ScreenOverlay Terminal Outro BRB)

      current="$(obs-cli scene get --port 4455)"
      prefix="''${current% *}"
      base="''${current##* }"

      index=-1
      for i in "''${!order[@]}"; do
        if [ "''${order[$i]}" = "$base" ]; then
          index=$i
          break
        fi
      done
      # Current scene isn't one of ours (OBS's own default "Scene", say)
      # — nothing sensible to step from, so do nothing rather than guess.
      if [ "$index" -eq -1 ]; then
        exit 0
      fi

      count=''${#order[@]}
      if [ "$direction" = next ]; then
        next_index=$(( (index + 1) % count ))
      else
        next_index=$(( (index - 1 + count) % count ))
      fi

      obs-cli scene current --port 4455 "$prefix ''${order[$next_index]}"
    '';
  };
in
{
  inherit obsScenePrefix kanataPlaySound obsSceneStep;
}
