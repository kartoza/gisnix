#!/usr/bin/env bash
#
# test-logs — copy /mnt/gisnix-install.log off the running
# `gisnix test-install`/`test-boot` QEMU VM into the repo root
# (gisnix-install.log, gitignored) so it's pasteable/greppable locally
# instead of photographing a screen.
#
#   gisnix test-logs
set -uo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$REPO_ROOT" ] || {
  echo "test-logs: not inside a git repository" >&2
  exit 1
}
cd "$REPO_ROOT" || exit 1

# shellcheck source=lib/test-vm.sh disable=SC1091
. "$REPO_ROOT/utils/lib/test-vm.sh"

test_vm_require_reachable test-logs

dest="$REPO_ROOT/gisnix-install.log"
if ! sshpass -p gisnix scp -P "$TEST_VM_SSH_PORT" "${TEST_VM_SSH_OPTS[@]}" \
  root@localhost:/mnt/gisnix-install.log "$dest"; then
  echo "test-logs: scp failed — is /mnt/gisnix-install.log there yet?" >&2
  echo "  (it's only created once disko has mounted /mnt and the install has started writing to it)" >&2
  exit 1
fi

echo "Saved to $dest"
