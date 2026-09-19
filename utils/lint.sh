#!/usr/bin/env bash
#
# lint — read-only static analysis over the whole repo.
#
# Ported from the personal-servers flake so both projects lint the same way.
# Runs every tool that is on PATH (inside `nix develop` they all are; via
# `gisnix lint` they come from the command's declared deps), reports ALL
# findings rather than stopping at the first, and exits non-zero if any tool
# fails.
#
# This is the repo-wide sweep. The pre-commit hooks (`gisnix hooks`) run a
# fast staged-only subset on every commit; `gisnix test` runs the flake
# checks, which additionally build NixOS test VMs.
set -uo pipefail

fail=0
have() { command -v "$1" >/dev/null 2>&1; }
run() { # label  cmd...
  local label="$1"
  shift
  printf '▶ %s\n' "$label"
  if "$@"; then printf '  ✓ %s\n' "$label"; else printf '  ✗ %s\n' "$label"; fail=1; fi
}
skip() { printf '· %s not on PATH — skipped (run from the nix develop shell)\n' "$1"; }

# Collect tracked files by type once. git ls-files respects .gitignore, which
# matters here: the tree carries an untracked copy of another flake and a
# multi-gigabyte model directory, and neither should be linted.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  mapfile -t nix_files < <(git ls-files '*.nix')
  mapfile -t sh_files < <(git ls-files '*.sh')
  mapfile -t py_files < <(git ls-files '*.py')
else
  mapfile -t nix_files < <(find . -name '*.nix' -not -path './.git/*')
  mapfile -t sh_files < <(find . -name '*.sh' -not -path './.git/*')
  mapfile -t py_files < <(find . -name '*.py' -not -path './.git/*')
fi

if [ "${#nix_files[@]}" -gt 0 ]; then
  if have nixfmt; then
    run "nixfmt --check    (nix formatting)" nixfmt --check "${nix_files[@]}"
  else skip nixfmt; fi
fi

if [ "${#sh_files[@]}" -gt 0 ]; then
  if have shellcheck; then
    run "shellcheck       (bash static analysis)" shellcheck -x "${sh_files[@]}"
  else skip shellcheck; fi
fi

if [ "${#py_files[@]}" -gt 0 ]; then
  if have ruff; then
    run "ruff check       (python lint)" ruff check "${py_files[@]}"
  else skip ruff; fi
fi

if have statix; then run "statix check     (nix anti-patterns)" statix check .; else skip statix; fi
if have deadnix; then run "deadnix          (unused nix bindings)" deadnix --fail .; else skip deadnix; fi
if have reuse; then run "reuse lint       (SPDX / licence headers)" reuse lint; else skip reuse; fi
if have gitleaks; then
  run "gitleaks detect  (secret scan, full history)" \
    gitleaks detect --redact --no-banner
else skip gitleaks; fi

echo
if [ "$fail" -eq 0 ]; then
  echo "✓ lint passed"
else
  echo "✗ lint found issues — see the ✗ lines above"
fi
exit "$fail"
