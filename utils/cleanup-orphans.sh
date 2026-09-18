#!/usr/bin/env bash
#
# Remove zfs-backup orphaned snapshots from datasets that are NOT part of the
# backup set.
#
# Background
# ----------
# zfs-backup 1.6.0 is configured on abyss with the whole pool (NIXROOT) as its
# source. Steps 3 and 4 of a run snapshot and replicate all five datasets, but
# step 5 ("prune local snapshots -> bookmarks") only ever processes
# NIXROOT/home. Every other dataset therefore accumulates two snapshots per run
# forever. On abyss that reached 19.2G on NIXROOT/root (against a 30G quota with
# only 1.04G of live data) and 290G on NIXROOT/nix.
#
# See ZFS-BACKUP-RECURSIVE-SNAPSHOT-BUG.md for the full write-up.
#
# Safety
# ------
#   * Dry run by default. Destroys nothing without --yes.
#   * NIXROOT/home is NEVER touched. It is the one dataset still being backed
#     up, so its latest -Backup/syncoid_ snapshot is the incremental base for
#     the next send; destroying it would force a full re-send. Its autosnap_*
#     snapshots are live sanoid policy.
#   * @blank is NEVER touched. On "erase your darlings" hosts it is rolled back
#     to on every boot.
#   * Only zfs-backup's own naming patterns are matched. Nothing else.
#   * Snapshots are destroyed one at a time. Range expressions (pool/ds@a%b)
#     are deliberately not used -- they silently take out snapshots outside the
#     matched set.
#   * Holds and clones/dependents abort the run.
#
# This only removes LOCAL snapshots. The replicas under NIXBACKUPS/abyss/* are
# untouched; reclaiming space there is a separate decision.
#
# Usage:
#   bash utils/zfs-cleanup-orphans.sh          # dry run, changes nothing
#   bash utils/zfs-cleanup-orphans.sh --yes    # actually destroy

set -euo pipefail

POOL="NIXROOT"

# Datasets to clean: everything in the pool that is NOT NIXROOT/home.
DATASETS=(
  "NIXROOT"
  "NIXROOT/root"
  "NIXROOT/nix"
  "NIXROOT/overflow"
  "NIXROOT/atuin"
)

# The dataset that must never be touched.
PROTECTED_DATASET="NIXROOT/home"

# zfs-backup's own snapshot names, and nothing else:
#   NIXROOT/root@2026-05-17.22h-55-Backup
#   NIXROOT/root@syncoid_abyss_2026-05-19:00:49:53-GMT01:00
PATTERN='@([0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]{2}h-[0-9]{2}-Backup$|syncoid_)'

APPLY=false
[[ "${1:-}" == "--yes" ]] && APPLY=true

ZFS="sudo zfs"
LIST=$(mktemp)
trap 'rm -f "$LIST"' EXIT

bar() { printf '%s\n' "──────────────────────────────────────────────────────────────"; }

bar
if $APPLY; then
  echo "MODE: DESTROY -- snapshots will be permanently removed"
else
  echo "MODE: DRY RUN -- nothing will be changed (pass --yes to destroy)"
fi
bar

echo
echo "Space before:"
$ZFS list -o name,used,usedbysnapshots,usedbydataset,refer,quota,avail -r "$POOL"

# ---------------------------------------------------------------- build list
echo
echo "Matching snapshots:"
: > "$LIST"
for ds in "${DATASETS[@]}"; do
  # -d 1 keeps this to the dataset itself, never its children.
  matches=$($ZFS list -H -t snapshot -o name -d 1 "$ds" 2>/dev/null \
            | grep -E "^${ds}${PATTERN}" || true)
  count=$(printf '%s' "$matches" | grep -c . || true)
  printf '  %-20s %s snapshot(s)\n' "$ds" "$count"
  [[ -n "$matches" ]] && printf '%s\n' "$matches" >> "$LIST"
done

TOTAL=$(grep -c . "$LIST" || true)
echo
echo "Total matched: $TOTAL"

if [[ "$TOTAL" -eq 0 ]]; then
  echo "Nothing to do."
  exit 0
fi

# ------------------------------------------------------------ safety asserts
echo
echo "Safety checks:"

if grep -q "^${PROTECTED_DATASET}@" "$LIST"; then
  echo "  ABORT: list contains ${PROTECTED_DATASET} snapshots. Refusing."
  exit 1
fi
echo "  OK: no ${PROTECTED_DATASET} snapshots in list"

if grep -qE '@blank$' "$LIST"; then
  echo "  ABORT: list contains an @blank snapshot. Refusing."
  exit 1
fi
echo "  OK: no @blank snapshot in list"

if grep -qE '@autosnap_' "$LIST"; then
  echo "  ABORT: list contains sanoid autosnap_ snapshots. Refusing."
  exit 1
fi
echo "  OK: no sanoid autosnap_ snapshots in list"

# Holds would make a destroy fail; surface them up front.
holds=0
while read -r snap; do
  [[ -z "$snap" ]] && continue
  if [[ -n "$($ZFS holds -H "$snap" 2>/dev/null)" ]]; then
    echo "  HOLD on $snap"
    holds=$((holds + 1))
  fi
done < "$LIST"
if [[ "$holds" -gt 0 ]]; then
  echo "  ABORT: $holds snapshot(s) have holds. Resolve before proceeding."
  exit 1
fi
echo "  OK: no holds"

# A snapshot with a clone cannot be safely destroyed. zfs destroy -nv reports
# any dependents, so anything beyond the snapshot's own line is a red flag.
deps=0
while read -r snap; do
  [[ -z "$snap" ]] && continue
  out=$($ZFS destroy -nv "$snap" 2>&1 || true)
  if printf '%s' "$out" | grep -qiE 'clone|dependent|cannot destroy'; then
    echo "  DEPENDENT: $snap"
    printf '%s\n' "$out" | sed 's/^/      /'
    deps=$((deps + 1))
  fi
done < "$LIST"
if [[ "$deps" -gt 0 ]]; then
  echo "  ABORT: $deps snapshot(s) have clones/dependents. Refusing."
  exit 1
fi
echo "  OK: no clones or dependents"

# ------------------------------------------------------------------- the list
echo
bar
echo "Snapshots that would be destroyed:"
bar
cat "$LIST"
bar

if ! $APPLY; then
  echo
  echo "DRY RUN -- nothing was changed."
  echo "Review the list above, then re-run with:"
  echo "    bash utils/zfs-cleanup-orphans.sh --yes"
  exit 0
fi

# ---------------------------------------------------------------- destroy
echo
read -r -p "Type DESTROY to permanently remove these $TOTAL snapshots: " reply
if [[ "$reply" != "DESTROY" ]]; then
  echo "Aborted -- nothing was changed."
  exit 1
fi

echo
failed=0
while read -r snap; do
  [[ -z "$snap" ]] && continue
  if $ZFS destroy -v "$snap"; then :; else
    echo "  FAILED: $snap"
    failed=$((failed + 1))
  fi
done < "$LIST"

echo
echo "Space after:"
$ZFS list -o name,used,usedbysnapshots,usedbydataset,refer,quota,avail -r "$POOL"

echo
if [[ "$failed" -gt 0 ]]; then
  echo "Completed with $failed failure(s)."
  exit 1
fi
echo "Done. $TOTAL snapshot(s) destroyed."
echo
echo "NOTE: space is only reclaimed once the LAST snapshot pinning a block is"
echo "gone, so per-snapshot USED figures understate what this frees. Compare"
echo "the usedbysnapshots columns above."
