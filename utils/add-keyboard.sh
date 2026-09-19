#!/usr/bin/env bash
#
# add-keyboard — find a connected keyboard's device identity and print a
# ready-to-paste kanata instance for it.
#
#   gisnix add-keyboard
#
# THE DEFAULT KANATA INSTANCE ALREADY COVERS EVERY KEYBOARD.
#
# services/device/input-kanata/kanata-keyboard.nix matches `devices = [ ]`, which
# kanata treats as "every keyboard on the system" — plug in a second
# board and it gets the same home-row mods and navigation layer as the
# first, with no configuration at all. Run this command only when a board
# needs its OWN, DIFFERENT instance: an ortholinear or split board whose
# physical layout doesn't match a standard row-staggered keyboard, one
# that should keep its factory layout untouched, or one running its own
# separate chord set. See docs/user/keyboard.md.
#
# What this does:
#   1. list connected keyboards with their evdev name and /dev/input path
#   2. let you pick one
#   3. print a `services.kanata.keyboards.<name>` block scoped to it,
#      ready to paste into your host's own kanata override file
#
# It does not write anything — you decide where the block belongs, the
# same way `gisnix configure`'s "edit mode" hands you a diff rather than
# guessing which file to change.
set -uo pipefail

if ! command -v libinput >/dev/null 2>&1; then
  echo "add-keyboard: needs libinput-tools on PATH — enter the dev shell," >&2
  echo "  or on an installed host: nix-shell -p libinput" >&2
  exit 1
fi

echo "Connected keyboards (via libinput):"
echo ""

# libinput list-devices prints stanzas separated by blank lines, one
# per device; keep the ones that advertise a keyboard capability.
mapfile -t stanzas < <(libinput list-devices 2>/dev/null | awk -v RS='' '{print; print "---GISNIX-SEP---"}')

names=()
paths=()
i=0
for stanza in "${stanzas[@]}"; do
  [ "$stanza" = "---GISNIX-SEP---" ] && continue
  echo "$stanza" | grep -qi "Capabilities:.*keyboard" || continue
  name=$(echo "$stanza" | awk -F':[[:space:]]*' '/^Device:/{print $2; exit}')
  kernel=$(echo "$stanza" | awk -F':[[:space:]]*' '/^Kernel:/{print $2; exit}')
  [ -n "$name" ] || continue
  i=$((i + 1))
  names+=("$name")
  paths+=("$kernel")
  printf '  %d) %-40s %s\n' "$i" "$name" "$kernel"
done

if [ "$i" -eq 0 ]; then
  echo "  (none found — is this running as a user in the input group?)"
  exit 1
fi

echo ""
printf "Pick a keyboard [1-%d]: " "$i"
read -r choice
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$i" ]; then
  echo "add-keyboard: not a valid choice" >&2
  exit 1
fi

idx=$((choice - 1))
picked_name="${names[$idx]}"
picked_path="${paths[$idx]}"
# by-id is stable across reconnects/reboots; by-path is not. Prefer by-id
# when udev has created one for this device.
stable_path=""
for by_id in /dev/input/by-id/*-event-kbd; do
  [ -e "$by_id" ] || continue
  if [ "$(readlink -f "$by_id")" = "$(readlink -f "$picked_path")" ]; then
    stable_path="$by_id"
    break
  fi
done
device_path="${stable_path:-$picked_path}"

# A safe, unique instance name: lowercase, non-alnum runs collapsed to "-".
instance_name=$(echo "$picked_name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')

cat <<NIX

Paste this into your host's kanata override (or a new
software/services/device/input-kanata/ module if you keep several), then rebuild:

  # ${picked_name}
  # Detected at ${device_path}. If this board ever needs a DIFFERENT
  # layout to the shared one (an ortholinear/split board, for instance),
  # write your own config here instead of importing kanata-config.nix —
  # see docs/user/keyboard.md for the shared layer's key reference.
  services.kanata.keyboards.${instance_name} = {
    devices = [ "${device_path}" ];
    extraDefCfg = ''
      process-unmapped-keys yes
    '';
    # The import path below is relative to wherever you paste this — from
    # a host file (hosts/<name>/*.nix) it's "gisnixRoot +
    # /software/services/device/input-kanata/kanata-config.nix" (this module
    # needs to receive gisnixRoot, same as hosts/example/disks.nix does);
    # from inside services/device/input-kanata/ itself it's just
    # "./kanata-config.nix". Fix the path to match where this landed.
    config = import ./kanata-config.nix {
      layout = "us"; # match hostConfig.kanataLayout if you set one
    };
  };
NIX
