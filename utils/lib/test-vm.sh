#!/usr/bin/env bash
# Shared by test-shell.sh and test-logs.sh — both talk to the QEMU VM
# `gisnix test-install`/`test-boot` launch, over the localhost-only
# hostfwd port those apps set up (see flake.nix). The VM's host key
# changes every time the ISO is rebuilt, and this is never reachable
# beyond localhost, so there is nothing worth verifying it against.

TEST_VM_SSH_PORT=2222
# shellcheck disable=SC2034  # used by test-shell.sh/test-logs.sh, which source this file
TEST_VM_SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
)

# $1: this command's name, used in the hint printed on failure.
test_vm_require_reachable() {
  if ! timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/${TEST_VM_SSH_PORT}" 2>/dev/null; then
    echo "$1: nothing listening on localhost:${TEST_VM_SSH_PORT}." >&2
    echo "  Run 'gisnix test-install' first (or 'gisnix test-boot' to relaunch an existing ISO)." >&2
    exit 1
  fi
}
