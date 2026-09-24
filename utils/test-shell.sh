#!/usr/bin/env bash
#
# test-shell — SSH into the running `gisnix test-install`/`test-boot` QEMU
# VM. Password auth, auto-supplied — this VM's root password is the
# well-known installer default ("gisnix"), same as everywhere else in this
# repo that talks about it.
#
#   gisnix test-shell
set -uo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$REPO_ROOT" ] || {
  echo "test-shell: not inside a git repository" >&2
  exit 1
}

# shellcheck source=lib/test-vm.sh disable=SC1091
. "$REPO_ROOT/utils/lib/test-vm.sh"

test_vm_require_reachable test-shell

exec sshpass -p gisnix ssh -p "$TEST_VM_SSH_PORT" "${TEST_VM_SSH_OPTS[@]}" root@localhost
