#!/usr/bin/env bash
#
# dev-help — render the operator-command cheat-sheet from utils/commands.json
# as a grid-lined table. Called by the dev shell's shellHook and by `gisnix`.
#
# Self-minting: add a row to commands.json and it appears here, in `nix run`,
# and in the Neovim menu, with no edit to any of the three.
#
# Commands are grouped; each group gets a brand-coloured banner and the
# leftmost column numbers within the group, restarting at 1. A row whose
# script is not written yet is shown dimmed with a marker rather than hidden —
# the manifest describes the intended lifecycle, and hiding the unwritten half
# would make the menu look arbitrary.
#
# The <leader>p<key> binding comes from the same manifest but is NOT shown
# here: it is meaningless outside Neovim, which labels its own menu.
set -uo pipefail

# Exiting quietly here would make the dev shell's banner silently lose a
# section, which reads as a bug in the shellHook rather than a missing tool.
command -v jq > /dev/null 2>&1 || {
  echo "gisnix: jq is not on PATH — enter the dev shell first:  nix develop" >&2
  exit 0
}
[ -f utils/commands.json ] || {
  echo "gisnix: run from the repo root (utils/commands.json missing)" >&2
  exit 0
}

# Brand palette (24-bit truecolor).
GREEN=$'\033[38;2;88;150;50m'   # env
YELLOW=$'\033[38;2;240;230;74m' # dns
BLUE=$'\033[38;2;147;176;35m'   # host
ORANGE=$'\033[38;2;238;121;19m' # secrets
EMBER=$'\033[38;2;185;78;40m'   # keycloak
DUSK=$'\033[38;2;126;118;143m'  # docs
TEAL=$'\033[38;2;74;170;160m'   # qa
SLATE=$'\033[38;2;110;130;150m' # storage
MAUVE=$'\033[38;2;158;120;160m' # hardware
STEEL=$'\033[38;2;120;140;135m' # vm
MOSS=$'\033[38;2;120;150;110m'  # software
DIM=$'\033[2m'
BOLD=$'\033[1m'
NC=$'\033[0m'

NW=2
CW=23
DW=46
SPAN=$((NW + CW + DW + 8))

dashes() {
  local n="$1" s=''
  while [ "$n" -gt 0 ]; do
    s="${s}─"
    n=$((n - 1))
  done
  printf '%s' "$s"
}
rule() { # $1=left  $2=tee  $3=right
  printf '%s%s%s%s%s%s%s\n' \
    "$1" "$(dashes $((NW + 2)))" "$2" "$(dashes $((CW + 2)))" "$2" "$(dashes $((DW + 2)))" "$3"
}
row() { # num  command  desc  present
  local d="$3" present="${4:-1}" name="$2" pre='' post=''
  d="${d//→/->}"
  d="${d//…/...}"
  d="${d//·/-}"
  if [ "$present" != "1" ]; then
    d="${d} ·pending"
    pre="$DIM"
    post="$NC"
  fi
  [ "${#d}" -gt "$DW" ] && d="${d:0:$((DW - 1))}~"
  printf '│ %*s │ %s%-*s%s │ %s%-*s%s │\n' \
    "$NW" "$1" "$pre" "$CW" "$name" "$post" "$pre" "$DW" "$d" "$post"
}

# Icons must be SINGLE-codepoint emoji. A variation selector counts as two
# characters for ${#…} but still renders in two cells, which overruns the
# banner row and breaks the grid.
group_meta() { # $1=group -> ICON COLOR LABEL
  case "$1" in
    host) ICON='🔧' COLOR=$BLUE LABEL='host      · provision, update, retire' ;;
    secrets) ICON='🔐' COLOR=$ORANGE LABEL='secrets   · agenix & provisioning' ;;
    env) ICON='🌱' COLOR=$GREEN LABEL='env       · build environment' ;;
    keycloak) ICON='🔑' COLOR=$EMBER LABEL='keycloak  · identity (company IdP)' ;;
    dns) ICON='🌐' COLOR=$YELLOW LABEL='dns       · filtering & resolution' ;;
    qa) ICON='🧪' COLOR=$TEAL LABEL='qa        · tests, lint & hooks' ;;
    docs) ICON='📚' COLOR=$DUSK LABEL='docs      · build & preview' ;;
    software) ICON='📦' COLOR=$MOSS LABEL='software  · bundles & packages' ;;
    storage) ICON='💾' COLOR=$SLATE LABEL='storage   · ZFS' ;;
    hardware) ICON='🎹' COLOR=$MAUVE LABEL='hardware  · keyboards & firmware' ;;
    vm) ICON='💻' COLOR=$STEEL LABEL='vm        · local machines' ;;
    *) ICON='📦' COLOR=$NC LABEL="$1" ;;
  esac
}
group_header() {
  group_meta "$1"
  local pad=$((SPAN - 3 - ${#LABEL}))
  ((pad < 0)) && pad=0
  printf '│ %s%s %s%s%*s│\n' "$COLOR$BOLD" "$ICON" "$LABEL" "$NC" "$pad" ''
}

# How to actually run these was the first thing a reader needed and the last
# thing the header said. Inside `nix develop` the commands are on PATH, so the
# name in the table IS the command; outside it they are flake apps.
# All commands are namespaced under `gisnix`. Probing for the dispatcher rather
# than IN_NIX_SHELL, because that variable is set by ANY nix shell and is
# therefore true in plenty of places where `gisnix` is not on PATH.
if command -v gisnix > /dev/null 2>&1; then
  echo "🚀 ${BOLD}Run any command below as${NC} ${BOLD}gisnix <command>${NC}"
  echo "   ${DIM}e.g.  gisnix installer --mock   ·   gisnix update example   ·   gisnix docs-serve${NC}"
  echo "   ${DIM}outside this shell:  nix run .#gisnix -- <command>${NC}"
else
  echo "🚀 ${BOLD}Operator commands${NC}"
  echo "   ${DIM}run one with:  nix run .#gisnix -- <command>${NC}"
  echo "   ${DIM}or enter the dev shell (nix develop), where it is just:  gisnix <command>${NC}"
fi
echo
rule ┌ ┬ ┐
row "#" "command" "what it does"

# A row is "present" when its script exists and every prelude it names exists
# too — the same test flake.nix applies before minting the app, so the marker
# here and the availability of `nix run .#<name>` never disagree.
# Sorted by the declared group order, not alphabetically. `sort_by(.group, …)`
# put dns first and host fifth, which throws away the lifecycle reading the
# grouping exists to convey.
#
# The element has to be bound before the lookup. Inside `index(...)` jq's `.`
# is the array being searched, not the command, so `$order | index(.group)`
# looks for `.group` ON THE ARRAY — which is null. That silently returned
# nothing for every row, and because the failure was invisible the cheat-sheet
# rendered with only its hand-written docs section and no manifest groups at
# all.
# Exit status, not message text, decides whether this worked.
#
# An earlier guard matched on the output starting with "jq:", which a
# different failure — a missing interpreter, a wrapper erroring — does not.
# The error text then flowed into the table and was rendered AS A ROW.
if ROWS="$(
  jq -r '
    (.groups // []) as $order
    | .commands
    | map(. as $c | $c + {rank: (($order | index($c.group)) // 99)})
    | sort_by(.rank, .order)
    | .[]
    | [ .group, .name, (.terse // .desc), .file, ((.prelude // []) | join(",")) ]
    | @tsv' utils/commands.json 2>&1
)"; then
  :
else
  echo "${DIM}could not read utils/commands.json — the command list is missing:${NC}" >&2
  printf '  %s\n' "$ROWS" >&2
  ROWS=""
fi

# And the shape is checked, not assumed: five tab-separated fields per row.
# Anything else means the query changed without this renderer changing with it.
if [ -n "$ROWS" ] && ! printf '%s' "$ROWS" | head -1 | grep -qP '^([^\t]*\t){4}[^\t]*$'; then
  echo "${DIM}unexpected row shape from commands.json — expected 5 fields${NC}" >&2
  ROWS=""
fi

# `printf '%s\n' ""` still emits one blank line, which the loop below reads as
# a record and renders as an empty row. Feed it nothing at all instead.
if [ -z "$ROWS" ]; then printf ''; else printf '%s\n' "$ROWS"; fi |
  {
    prev=''
    n=0
    total=0
    ready=0
    while IFS=$'\t' read -r g name desc file prelude; do
      present=1
      [ -f "utils/${file}" ] || present=0
      if [ -n "$prelude" ]; then
        IFS=',' read -ra libs <<< "$prelude"
        for lib in "${libs[@]}"; do [ -f "utils/lib/${lib}" ] || present=0; done
      fi
      total=$((total + 1))
      [ "$present" = "1" ] && ready=$((ready + 1))

      if [ "$g" != "$prev" ]; then
        rule ├ ┴ ┤
        group_header "$g"
        rule ├ ┬ ┤
        prev="$g"
        n=0
      fi
      n=$((n + 1))
      row "$n" "$name" "$desc" "$present"
    done

    # Docs apps are hand-written in flake.nix rather than declared in the
    # manifest: they interpolate store paths and a python environment, which a
    # JSON row cannot express. Rendered here so the cheat-sheet is complete.
    rule ├ ┴ ┤
    group_header docs
    rule ├ ┬ ┤
    row 1 "docs-serve" "live preview on http://localhost:8000"
    row 2 "docs-build" "build the static site (mkdocs build --strict)"
    row 3 "docs-generate-bundles" "regenerate docs/references/bundles.md"
    row 4 "docs-generate-commands" "regenerate docs/references/commands.md"
    row 5 "test-install" "build the installer ISO and boot it in QEMU"
    rule └ ┴ ┘

    echo
    printf '  %sper-host VMs are generated, not listed:%s  gisnix <host>-vm\n' "$DIM" "$NC"
    if [ "$ready" -lt "$total" ]; then
      printf '  %s%d of %d commands implemented; the rest are declared and marked above.%s\n' \
        "$DIM" "$ready" "$total" "$NC"
    fi
  }
