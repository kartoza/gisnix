#!/usr/bin/env bash
# shellcheck disable=SC2154  # palette/helpers come from the inlined prelude
#
# snapshot — take an on-demand ZFS snapshot, outside the sanoid schedule.
#
# sanoid already snapshots /home every fifteen minutes on the aligned quarters.
# This is for the other case: you are about to do something you might want to
# undo, and you want a snapshot you named and can find.
#
#   gisnix snapshot                        # this machine, all sanoid-managed datasets
#   gisnix snapshot myhost                 # a remote host
#   gisnix snapshot -- --label before-upgrade
#   gisnix snapshot -- --dataset rpool/home
#
# Snapshots are cheap and additive; nothing is destroyed here. They do consume
# space as the live data diverges, so `gisnix cleanup-orphans` exists for the
# tidying-up side.
set -uo pipefail

LABEL=""
DATASET=""
HOSTARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --label)
      LABEL="${2:-}"
      shift 2
      ;;
    --dataset)
      DATASET="${2:-}"
      shift 2
      ;;
    -h | --help)
      awk 'NR>1 && /^# shellcheck/ {next} NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
      exit 0
      ;;
    -*)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
    *)
      HOSTARG="$1"
      shift
      ;;
  esac
done

f_require_repo
HOST="$(f_resolve_host "$HOSTARG")" || exit 1
f_require_deployable "$HOST"
SELF="$(hostname -s 2>/dev/null || true)"

# A label has to survive being part of a snapshot name, so restrict it rather
# than let zfs reject the whole batch halfway through.
if [ -n "$LABEL" ]; then
  case "$LABEL" in
    *[!A-Za-z0-9_.-]*)
      f_die "label may only contain letters, digits, dot, dash and underscore"
      ;;
  esac
else
  LABEL="manual"
fi

echo
echo "${f_bold}Snapshot — ${HOST}${f_nc}  ${f_dim}label: ${LABEL}${f_nc}"

BODY=$(
  cat << 'REMOTE'
set -uo pipefail
command -v zfs >/dev/null 2>&1 || { echo "  no ZFS on this host"; exit 1; }

stamp=$(date +%Y-%m-%d-%H%M%S)
name="manual-${LABEL}-${stamp}"

if [ -n "$DATASET" ]; then
  targets="$DATASET"
else
  # Everything with com.sun:auto-snapshot or a sanoid policy is what we
  # actually care about; falling back to all filesystems would snapshot
  # scratch datasets that exist precisely because they are disposable.
  targets=$(zfs list -H -o name -t filesystem 2>/dev/null | grep -E '/home$|/home/|/persist' || true)
  [ -n "$targets" ] || targets=$(zfs list -H -o name -t filesystem 2>/dev/null | head -1)
fi

[ -n "$targets" ] || { echo "  no datasets to snapshot"; exit 1; }

echo "  datasets:"
printf '    %s\n' $targets

rc=0
for ds in $targets; do
  if sudo zfs snapshot "${ds}@${name}"; then
    printf '  \033[32m✓\033[0m %s@%s\n' "$ds" "$name"
  else
    printf '  \033[31m✗\033[0m %s@%s\n' "$ds" "$name"
    rc=1
  fi
done

echo
echo "  most recent snapshots:"
zfs list -t snapshot -o name,used,creation -s creation 2>/dev/null | tail -6 | sed 's/^/    /'
exit $rc
REMOTE
)

ENVPRE="LABEL=$(printf '%q' "$LABEL")
DATASET=$(printf '%q' "$DATASET")
"

if [ "$HOST" = "$SELF" ]; then
  printf '%s\n%s\n' "$ENVPRE" "$BODY" | bash
else
  printf '%s\n%s\n' "$ENVPRE" "$BODY" | f_ssh "$HOST" bash -s
fi
