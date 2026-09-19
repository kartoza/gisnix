#!/usr/bin/env bash
# shellcheck disable=SC2154  # palette/helpers come from the inlined prelude
#
# unlock — unlock a host's encrypted pool over initrd SSH so it can finish
# booting.
#
# A host with an encrypted root stops early in boot and runs a tiny SSH daemon
# on a dedicated port, waiting for the passphrase. Until it gets one the
# machine pings but has no real SSH, which is indistinguishable from "still
# booting" unless you know to look — `check` reports the difference.
#
#   gisnix unlock myhost
#
# The initrd has no overlay networking, so this only works from the same LAN
# segment. The port and address come from hosts/fleet.nix.
set -uo pipefail

# The SC2154 disable at the top of this file is because the colour palette
# and helper functions live in utils/lib/fleet.sh, which the manifest's
# `prelude` inlines ahead of this script at build time. Linting the file on
# its own cannot see them. The disable is scoped to SC2154, so genuine
# unassigned-variable typos still fail the build.

[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && {
  awk 'NR>1 && /^# shellcheck/ {next} NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
  exit 0
}

f_require_repo
HOST="$(f_resolve_host "${1:-}")" || exit 1
f_require_deployable "$HOST"

PORT="$(f_field "$HOST" initrdSshPort '')"
ADDR="$(f_field "$HOST" lanAddress '')"

[ -n "$PORT" ] || f_die "${HOST} has no initrdSshPort in hosts/fleet.nix — it has no
  encrypted pool standing between power-on and a finished boot."
[ -n "$ADDR" ] || f_die "${HOST} has no lanAddress in hosts/fleet.nix, so there is no
  address to reach its initrd on."

if f_port_open "$ADDR" 22; then
  echo "${f_green}${HOST} is already booted${f_nc} ${f_dim}— nothing to unlock.${f_nc}"
  echo "${f_dim}  If its DATA pools are still locked, run 'unlock-data' on the host.${f_nc}"
  exit 0
fi

f_port_open "$ADDR" "$PORT" || f_die "${HOST} is not at the unlock prompt (nothing on ${ADDR}:${PORT}).
  It may be powered off, or still in early boot. Check with:
    gisnix check ${HOST}"

echo "${f_bold}Unlocking ${HOST}${f_nc}  ${f_dim}${ADDR}:${PORT}${f_nc}"
echo "${f_dim}The passphrase prompt comes from the host's initrd, not from here.${f_nc}"
echo

# The initrd's sshd has its own host key, distinct from the booted system's on
# port 22. Pointing at a throwaway known-hosts file avoids a spurious
# host-key-changed warning every cold boot without weakening checking for the
# real host. LogLevel=ERROR silences the "permanently added" notice that
# choice produces, WITHOUT the blanket 2>/dev/null this used to carry — which
# also swallowed every real error the initrd had to report.
#
# WHY IT RUNS A COMMAND RATHER THAN OPENING A SHELL
#
# Under the SCRIPTED stage-1 initrd, sshd dropped you straight onto the
# passphrase prompt. The fleet's initrd is systemd stage-1 now — the Plymouth
# theme in software/services/system/boot-themes/ turns it on — and there you
# get a root shell instead, with the prompt waiting behind a password agent
# nobody told you to run. That is the `-bash-5.3#` you get from a bare ssh,
# and it looks exactly like a broken unlock.
#
# -t forces a TTY, which the agent needs to read a passphrase.
ssh -t -p "$PORT" \
  -o UserKnownHostsFile=/dev/null \
  -o StrictHostKeyChecking=no \
  -o LogLevel=ERROR \
  -o ConnectTimeout=10 \
  "root@${ADDR}" '
    if command -v systemd-tty-ask-password-agent >/dev/null 2>&1; then
      systemd-tty-ask-password-agent --query
    else
      echo "This initrd has no systemd password agent — it is the scripted"
      echo "stage-1, which normally prompts on its own. Dropping to a shell;"
      echo "try:  zfs load-key -a    then exit."
      exec /bin/sh -l
    fi
  '

echo
echo "${f_dim}Watch it finish booting with:  gisnix check ${HOST}${f_nc}"
