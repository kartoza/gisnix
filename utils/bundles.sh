#!/usr/bin/env bash
#
# bundles — what software bundles exist, and what is in them.
#
# A bundle is a directory under software/ carrying a bundle.json. That file
# names it, describes it, says what it implies and lists the modules in it, so
# the taxonomy and the package sets are one system rather than two.
#
#   kz bundles                    # every bundle, one line each
#   kz bundles desktop-gis        # one bundle in detail
#   kz bundles --unclaimed        # modules no bundle installs
#   kz bundles --tree             # the implication graph
#
# Read-only. The full reference, generated from the same files, is
# docs/references/bundles.md.
set -uo pipefail

GREEN=$'\033[38;2;88;150;50m'
YELLOW=$'\033[38;2;240;230;74m'
BLUE=$'\033[38;2;147;176;35m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
NC=$'\033[0m'

[ -d software ] || {
  echo "run from the repo root" >&2
  exit 1
}

MODE=list
TARGET=""
case "${1:-}" in
  -h | --help)
    awk 'NR>1 && /^# shellcheck/ {next} NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
    exit 0
    ;;
  --unclaimed) MODE=unclaimed ;;
  --tree) MODE=tree ;;
  "") ;;
  -*)
    echo "unknown argument: $1" >&2
    exit 1
    ;;
  *)
    MODE=detail
    TARGET="$1"
    ;;
esac

export KZ_MODE="$MODE" KZ_TARGET="$TARGET"
export KZ_GREEN="$GREEN" KZ_YELLOW="$YELLOW" KZ_BLUE="$BLUE"
export KZ_DIM="$DIM" KZ_BOLD="$BOLD" KZ_NC="$NC"

# The reading lives in docs/scripts/bundles.py, which is also what generates
# the reference page — one implementation, so the terminal and the docs cannot
# disagree about what a bundle contains.
exec python3 - <<'PYEOF'
import os, sys, textwrap
sys.path.insert(0, "docs/scripts")
import bundles

G, Y, B = os.environ["KZ_GREEN"], os.environ["KZ_YELLOW"], os.environ["KZ_BLUE"]
D, BOLD, NC = os.environ["KZ_DIM"], os.environ["KZ_BOLD"], os.environ["KZ_NC"]
mode, target = os.environ["KZ_MODE"], os.environ["KZ_TARGET"]

all_bundles = bundles.load()
index = {b["name"]: b for b in all_bundles}

if mode == "unclaimed":
    rows = [(b, m) for b in all_bundles for m in b.get("unclaimed", [])]
    print()
    if not rows:
        print(f"  {G}Every module in software/ is claimed by a bundle.{NC}")
        print(f"  {D}Nothing is sitting in the tree uninstalled and unexplained.{NC}")
    else:
        print(f"  {BOLD}Present but deliberately not installed{NC}")
        for b, m in rows:
            print(f"    {Y}{b['path']}/{m}{NC}")
    print()
    raise SystemExit(0)

if mode == "tree":
    children = {}
    for b in all_bundles:
        for dep in b.get("implies", []):
            children.setdefault(dep, []).append(b["name"])
    roots = [b["name"] for b in all_bundles if not b.get("implies")]

    def walk(name, prefix="", last=True):
        node = index[name]
        count = len(node.get("modules", []))
        mark = "└─ " if last else "├─ "
        print(f"  {prefix}{mark}{BOLD}{name}{NC} {D}({count}){NC}")
        kids = sorted(children.get(name, []))
        for i, k in enumerate(kids):
            walk(k, prefix + ("   " if last else "│  "), i == len(kids) - 1)

    print()
    for i, r in enumerate(roots):
        walk(r, "", i == len(roots) - 1)
    print()
    raise SystemExit(0)

if mode == "detail":
    b = index.get(target)
    if b is None:
        print(f"  no bundle named {target!r}", file=sys.stderr)
        print(f"  {D}known: {', '.join(sorted(index))}{NC}", file=sys.stderr)
        raise SystemExit(1)
    print()
    print(f"  {BOLD}{b['name']}{NC}  {D}software/{b['path']}/{NC}")
    print()
    # textwrap, not slicing: fixed-width slices break mid-word.
    for line in textwrap.wrap(b["description"], 72):
        print(f"  {line}")
    print()
    if b.get("selection") == "one-of":
        print(f"  {Y}A choice, not a set — a host takes exactly one of these.{NC}")
        print()
    if b.get("implies"):
        print(f"  {D}also brings in:{NC} {', '.join(b['implies'])}")
        print()
    for m in b.get("modules", []):
        print(f"    {G}•{NC} {m}")
    for m in b.get("unclaimed", []):
        print(f"    {Y}◌{NC} {m} {D}(present, not installed){NC}")
    print()
    raise SystemExit(0)

print()
print(f"  {BOLD}Software bundles{NC}  {D}a bundle is a directory under software/{NC}")
print(f"  {D}{'─' * 72}{NC}")
total = 0
for b in all_bundles:
    n = len(b.get("modules", []))
    total += n
    kind = f" {Y}choice{NC}" if b.get("selection") == "one-of" else ""
    dep = f"  {D}← {', '.join(b['implies'])}{NC}" if b.get("implies") else ""
    print(f"  {BOLD}{b['name']:<32}{NC}{n:>3}{kind}{dep}")
print(f"  {D}{'─' * 72}{NC}")
print(f"  {len(all_bundles)} bundles, {total} modules")
print()
print(f"  {B}💁{NC}  one in detail: {BOLD}kz bundles <name>{NC}   ·   "
      f"graph: {BOLD}kz bundles --tree{NC}")
print(f"  {D}    full reference: docs/references/bundles.md{NC}")
print()
PYEOF
