#!/usr/bin/env bash
#
# dns — inspect and temporarily pause the local DNS filtering.
#
# One implementation, four commands. Which one you invoked is taken from the
# name it was called as, so `dns-off`, `dns-on`, `dns-test` and `dns-status`
# are four rows in the menu but a single script:
#
#   dns-status   what is actually resolving: NetBird, blocky, upstream
#   dns-off      pause blocky for a while, then restore it automatically
#   dns-on       restore blocky now, cancelling any pending auto-restore
#   dns-test     open an ad-block test page and report the score
#
# WHY PAUSING IS TIME-BOXED
#
# Turning ad filtering off is a debugging action — reproducing what an
# unfiltered user sees. Left off it silently exposes the machine, and the
# person who turned it off is exactly the person who will forget. `dns-off`
# therefore schedules its own restore with a transient systemd timer, so the
# default outcome of walking away is that filtering comes back.
#
#   gisnix dns-off              # pause for 30 minutes
#   gisnix dns-off 5m        # pause for 5 minutes
#   gisnix dns-on               # restore now
#
# This changes RUNTIME state only. Nothing here edits the NixOS configuration:
# a rebuild, or a reboot, restores the declared state regardless.
set -uo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[38;2;88;150;50m'
YELLOW=$'\033[38;2;240;230;74m'
BLUE=$'\033[38;2;147;176;35m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
NC=$'\033[0m'

RESTORE_UNIT=blocky-restore
DEFAULT_PAUSE=30m

case "$(basename "$0")" in
  dns-off) MODE=off ;;
  dns-on) MODE=on ;;
  dns-test) MODE="test" ;;
  *) MODE=status ;;
esac

[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && {
  awk 'NR>1 && /^# shellcheck/ {next} NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
  exit 0
}

have() { command -v "$1" > /dev/null 2>&1; }

blocky_active() { systemctl is-active --quiet blocky; }

pending_restore() {
  systemctl list-timers --all --no-legend --no-pager 2>/dev/null |
    grep -q "${RESTORE_UNIT}"
}

# ── status ─────────────────────────────────────────────────────────────────

show_status() {
  echo
  echo "${BOLD}DNS status${NC}  ${DIM}$(hostname -s 2>/dev/null || echo '')${NC}"
  echo "${DIM}──────────────────────────────────────────────────────────────${NC}"

  if blocky_active; then
    echo "  blocky            ${GREEN}running${NC}  ${DIM}(filtering on 127.0.0.1:53)${NC}"
  else
    echo "  blocky            ${RED}stopped${NC}  ${DIM}(no ad/tracker filtering)${NC}"
  fi

  if pending_restore; then
    WHEN="$(systemctl list-timers --all --no-legend --no-pager 2>/dev/null |
      grep "${RESTORE_UNIT}" | awk '{print $1, $2, $3}')"
    echo "  auto-restore      ${YELLOW}scheduled${NC}  ${DIM}${WHEN}${NC}"
  fi

  # NetBird publishes its own resolvers when the host joins the overlay. Those
  # must be honoured — company-internal names only resolve through them — so
  # this reports what NetBird is offering rather than treating it as a
  # conflict with blocky.
  if have netbird && netbird status > /dev/null 2>&1; then
    NB="$(netbird status 2>/dev/null | sed -n 's/^ *NetBird IP: *//p' | head -1)"
    echo "  netbird           ${GREEN}connected${NC}  ${DIM}${NB:-}${NC}"
    netbird status --detail 2>/dev/null | sed -n 's/^ *Nameservers: *//p' |
      head -1 | sed "s/^/  overlay resolvers  ${DIM}/;s/$/${NC}/"
  elif have netbird; then
    echo "  netbird           ${DIM}not connected${NC}"
  fi

  if have resolvectl; then
    echo
    echo "${BOLD}  systemd-resolved${NC}"
    resolvectl status 2>/dev/null |
      grep -E 'Current DNS Server|DNS Servers|DNS Domain' |
      sed "s/^/  ${DIM}/;s/$/${NC}/" | head -8
  fi

  echo
  echo "${BOLD}  resolution check${NC}"
  for probe in kartoza.com doubleclick.net; do
    ANS="$(getent hosts "$probe" 2>/dev/null | awk '{print $1}' | head -1)"
    case "$ANS" in
      '') printf '    %-18s %s\n' "$probe" "${DIM}no answer${NC}" ;;
      0.0.0.0 | ::) printf '    %-18s %s\n' "$probe" "${GREEN}blocked${NC}" ;;
      *) printf '    %-18s %s\n' "$probe" "${ANS}" ;;
    esac
  done
  echo "${DIM}──────────────────────────────────────────────────────────────${NC}"
}

# ── off / on ───────────────────────────────────────────────────────────────

do_off() {
  local pause="${1:-$DEFAULT_PAUSE}"

  blocky_active || {
    echo "${YELLOW}blocky is already stopped.${NC}"
    pending_restore && echo "${DIM}An auto-restore is still scheduled — dns-on cancels it.${NC}"
    exit 0
  }

  echo "${BOLD}Pausing DNS filtering for ${pause}${NC}"
  echo "${DIM}You will see ads and trackers until it comes back.${NC}"

  sudo systemctl stop blocky || {
    echo "${RED}✗ could not stop blocky${NC}"
    exit 1
  }

  # Cancel any earlier timer first, so a second dns-off extends the pause
  # rather than leaving two timers racing to restore.
  sudo systemctl stop "${RESTORE_UNIT}.timer" 2> /dev/null || true

  sudo systemd-run --unit="${RESTORE_UNIT}" --on-active="${pause}" \
    --description="Restore blocky DNS filtering after a dns-off pause" \
    systemctl start blocky > /dev/null || {
    echo "${RED}✗ could not schedule the restore — turning filtering back on now${NC}"
    sudo systemctl start blocky
    exit 1
  }

  echo "${GREEN}✓ filtering paused${NC}  ${DIM}restores automatically in ${pause}${NC}"
  echo "${DIM}  bring it back sooner:  gisnix dns-on${NC}"
}

do_on() {
  sudo systemctl stop "${RESTORE_UNIT}.timer" 2> /dev/null || true
  sudo systemctl start blocky || {
    echo "${RED}✗ could not start blocky${NC}"
    exit 1
  }
  echo "${GREEN}✓ DNS filtering restored${NC}"
}

# ── test ───────────────────────────────────────────────────────────────────

do_test() {
  echo "${BOLD}Ad-blocking test${NC}"
  echo

  # A resolver-level check first: it works headless, needs no browser, and
  # answers the question the browser test only approximates.
  local blocked=0 total=0
  for domain in \
    doubleclick.net googleadservices.com googlesyndication.com \
    ads.yahoo.com adservice.google.com scorecardresearch.com \
    quantserve.com taboola.com outbrain.com criteo.com; do
    total=$((total + 1))
    ANS="$(getent hosts "$domain" 2>/dev/null | awk '{print $1}' | head -1)"
    case "$ANS" in
      '' | 0.0.0.0 | ::)
        blocked=$((blocked + 1))
        printf '  %-28s %s\n' "$domain" "${GREEN}blocked${NC}"
        ;;
      *) printf '  %-28s %s\n' "$domain" "${RED}resolved → ${ANS}${NC}" ;;
    esac
  done

  echo
  local pct=$((blocked * 100 / total))
  if [ "$pct" -ge 90 ]; then
    echo "  ${GREEN}${BOLD}${blocked}/${total} blocked  (${pct}%)${NC}"
  elif [ "$pct" -ge 50 ]; then
    echo "  ${YELLOW}${BOLD}${blocked}/${total} blocked  (${pct}%)${NC}"
  else
    echo "  ${RED}${BOLD}${blocked}/${total} blocked  (${pct}%)${NC}"
    blocky_active || echo "  ${DIM}blocky is stopped — run: gisnix dns-on${NC}"
  fi

  echo
  echo "${BLUE}💁${NC}  Browser-level test (catches what the resolver cannot — in-page"
  echo "    scripts, cosmetic filtering):"
  local url="https://d3ward.github.io/toolz/adblock"
  echo "    ${url}"
  if have xdg-open; then
    xdg-open "$url" > /dev/null 2>&1 &
    echo "${DIM}    opening…${NC}"
  fi
}

case "$MODE" in
  status) show_status ;;
  off) do_off "${1:-}" ;;
  on) do_on ;;
  test) do_test ;;
esac
