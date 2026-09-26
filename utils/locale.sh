#!/usr/bin/env bash
#
# locale — change this machine's locale without hand-editing config.nix.
#
#   gisnix locale            # show current settings, then an interactive menu
#   gisnix locale --show     # just print the current settings and exit
#
# A host has one preset locale (keyboard + timezone + language + regional
# formatting, from software/locale/locales.json) plus three optional
# overrides that change ONE axis each — most usefully the clock while
# travelling. This writes those into hosts/<host>/config.nix and offers to
# rebuild, so:
#
#   travelling to Zurich, English desktop, Portuguese number formatting:
#     start from the `pt-en` preset, override the timezone to Europe/Zurich
#   back home:
#     clear the timezone override — the preset's Europe/Lisbon returns
set -uo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$REPO_ROOT" ] || {
  echo "locale: not inside a git repository" >&2
  exit 1
}
cd "$REPO_ROOT" || exit 1

BOLD=$'\033[1m'
DIM=$'\033[2m'
NC=$'\033[0m'

EDIT="python3 $REPO_ROOT/utils/lib/locale_edit.py"
MANIFEST="$REPO_ROOT/software/locale/locales.json"

hosts() { find hosts -mindepth 2 -maxdepth 2 -name config.nix -printf '%h\n' | xargs -n1 basename | sort; }

# Resolve the host the same way `gisnix update`/`vm` do: this machine.
self="$(hostname -s 2>/dev/null || true)"
if hosts | grep -qx "$self"; then
  HOST="$self"
else
  echo "locale: this machine (${self:-unknown}) is not a host in this flake." >&2
  echo "    Known hosts: $(hosts | tr '\n' ' ')" >&2
  exit 1
fi
CONFIG="hosts/$HOST/config.nix"

show() {
  local preset tz lang fmt
  preset=$($EDIT "$CONFIG" get | awk -F'\t' '$1=="locale"{print $2}')
  tz=$($EDIT "$CONFIG" get | awk -F'\t' '$1=="timeZone"{print $2}')
  lang=$($EDIT "$CONFIG" get | awk -F'\t' '$1=="language"{print $2}')
  fmt=$($EDIT "$CONFIG" get | awk -F'\t' '$1=="formatLocale"{print $2}')

  local label ptz plang pfmt
  label=$(jq -r --arg c "$preset" '.[] | select(.code==$c) | .label' "$MANIFEST" 2>/dev/null)
  ptz=$(jq -r --arg c "$preset" '.[] | select(.code==$c) | .timeZone' "$MANIFEST" 2>/dev/null)
  plang=$(jq -r --arg c "$preset" '.[] | select(.code==$c) | .uiLocale' "$MANIFEST" 2>/dev/null)
  pfmt=$(jq -r --arg c "$preset" '.[] | select(.code==$c) | .formatLocale' "$MANIFEST" 2>/dev/null)

  printf '  %s%s%s — locale\n\n' "$BOLD" "$HOST" "$NC"
  printf '  preset       %s%s%s  %s(%s)%s\n' "$BOLD" "$preset" "$NC" "$DIM" "${label:-unknown}" "$NC"
  printf '  clock        %s        %sfrom %s%s\n' "${tz:-$ptz}" "$DIM" "${tz:+override, }${tz:-preset}" "$NC"
  printf '  language     %s   %sfrom %s%s\n' "${lang:-$plang}" "$DIM" "${lang:+override, }${lang:-preset}" "$NC"
  printf '  formatting   %s   %sfrom %s%s\n' "${fmt:-$pfmt}" "$DIM" "${fmt:+override, }${fmt:-preset}" "$NC"
  echo
}

show
[ "${1:-}" = "--show" ] && exit 0

command -v gum >/dev/null || {
  echo "locale: gum not found — run inside 'gisnix' / the dev shell." >&2
  exit 1
}

action=$(gum choose --header "What would you like to change?" \
  "Change the preset locale" \
  "Override the clock (timezone)" \
  "Override the desktop language" \
  "Override number/date formatting" \
  "Clear an override" \
  "Cancel") || exit 0

changed=0
case "$action" in
  "Change the preset locale")
    code=$(jq -r '.[] | "\(.code)\t\(.label)"' "$MANIFEST" \
      | gum filter --header "Preset locale" --indicator ">" \
      | cut -f1) || exit 0
    [ -n "$code" ] && { $EDIT "$CONFIG" set locale "$code"; changed=1; }
    ;;
  "Override the clock (timezone)")
    tz=$(timedatectl list-timezones 2>/dev/null | gum filter --header "Timezone") || exit 0
    [ -n "$tz" ] && { $EDIT "$CONFIG" set timeZone "$tz"; changed=1; }
    ;;
  "Override the desktop language")
    lang=$(jq -r '[.[].uiLocale] | unique | .[]' "$MANIFEST" | gum filter --header "Desktop language (glibc locale)") || exit 0
    [ -n "$lang" ] && { $EDIT "$CONFIG" set language "$lang"; changed=1; }
    ;;
  "Override number/date formatting")
    fmt=$(jq -r '[.[].formatLocale] | unique | .[]' "$MANIFEST" | gum filter --header "Regional formatting (glibc locale)") || exit 0
    [ -n "$fmt" ] && { $EDIT "$CONFIG" set formatLocale "$fmt"; changed=1; }
    ;;
  "Clear an override")
    which=$(gum choose --header "Clear which override?" "clock" "language" "formatting" "all") || exit 0
    case "$which" in
      clock) $EDIT "$CONFIG" clear timeZone ;;
      language) $EDIT "$CONFIG" clear language ;;
      formatting) $EDIT "$CONFIG" clear formatLocale ;;
      all) $EDIT "$CONFIG" clear timeZone; $EDIT "$CONFIG" clear language; $EDIT "$CONFIG" clear formatLocale ;;
    esac
    changed=1
    ;;
  *) exit 0 ;;
esac

[ "$changed" -eq 1 ] || exit 0

echo
show
if gum confirm "Rebuild $HOST now to apply?"; then
  # The .#update flake app, not `bash utils/update.sh` — the app carries the
  # inlined fleet.sh prelude that update.sh needs; the bare script does not.
  exec nix --extra-experimental-features "nix-command flakes" run ".#update" -- "$HOST"
else
  printf '  %schange written to %s — run %sgisnix update%s when ready.%s\n' "$DIM" "$CONFIG" "$BOLD" "$NC$DIM" "$NC"
fi
