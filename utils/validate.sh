#!/usr/bin/env bash
#
# validate — the full static check bank, on demand.
#
# Commits run only the instant hooks (formatting, secret scan); everything
# else moved to pre-commit's `manual` stage so a commit never makes you
# wait. This runs the lot — the commit-stage hooks plus the manual bank
# (lint, bundle/resource/locale/brand/manifest consistency) — over the
# whole tree, exactly what CI enforces on every push and PR.
#
#   gisnix validate            # full static bank, all files
#   gisnix validate --staged   # only files staged right now
#
# The build/eval gates (example-host build, bundle eval) are NOT here —
# they stay on `git push` and in CI, where their minutes are already paid.
set -uo pipefail

[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && {
  awk 'NR>1 && /^# shellcheck/ {next} NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
  exit 0
}

SCOPE=(--all-files)
[ "${1:-}" = "--staged" ] && SCOPE=()

fail=0
echo "▸ commit-stage hooks (formatting, secrets)"
pre-commit run "${SCOPE[@]}" --hook-stage pre-commit || fail=1
echo
echo "▸ the manual bank (lint and consistency checks)"
pre-commit run "${SCOPE[@]}" --hook-stage manual || fail=1

echo
if [ $fail -eq 0 ]; then
  echo "✅  validate: all checks passed"
else
  echo "❌  validate: failures above"
fi
exit $fail
