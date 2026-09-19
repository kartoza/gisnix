#!/usr/bin/env python3
"""Fail when one host would receive a package from two declarations.

Nix does not complain about this. `environment.systemPackages` is a list that
concatenates, and the same derivation appearing twice produces one entry in
the closure — so a duplicate is invisible at build time and forever after.

It is still a defect, and an expensive one:

  * removing the package from the module you found does nothing, because the
    other declaration still installs it. `gisnix configure`'s delete does exactly
    this, and would report success while the package stayed
  * the two copies drift. `software/base/fetchers.nix` and `utilities.nix`
    both listed `btop`; either could have been pinned, overridden or dropped
    without the other moving
  * it makes the catalogue lie about where software comes from

WHAT COUNTS AS A DUPLICATE

One host receiving the same package from two files. That definition matters,
because two weaker ones produce nonsense:

  * "declared in two files anywhere" flags `software/locale/*.nix`, which all
    list `aspell`. A host takes exactly ONE locale — they are alternatives,
    not duplicates
  * it also flags two different hosts configuring the same model of
    keyboard. Those are different machines; neither gets the package twice

So this resolves each host's bundles, adds its own files, and looks for a
package arriving from more than one of them.

Run from the repo root:  python3 utils/check-duplicates.py
Also wired into pre-commit.
"""

from __future__ import annotations

import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "utils" / "lib"))

import bundleinfo as I  # noqa: E402
import hostconfig as H  # noqa: E402


def modules_for(host: str) -> list[Path]:
    """Every module a host receives: its bundles', its locale's, and its own."""
    config = H.parse(H.path_for(host))
    index = {b["name"]: b for b in H.catalogue()}

    found: list[Path] = []
    for name in H.resolve(sorted(config.enabled)):
        bundle = index.get(name)
        if bundle:
            found += [
                ROOT / "software" / bundle["path"] / m for m in bundle.get("modules", [])
            ]
    if config.locale:
        found.append(ROOT / "software" / "locale" / f"locale-{config.locale}.nix")
    found += sorted((ROOT / "hosts" / host).glob("*.nix"))
    return [m for m in found if m.exists()]


def main() -> int:
    problems: dict[tuple[str, tuple[str, ...]], set[str]] = defaultdict(set)

    for host in H.hosts():
        declared: dict[str, list[str]] = defaultdict(list)
        for module in modules_for(host):
            for package in I.packages_in(module)[0]:
                declared[package].append(str(module.relative_to(ROOT)))
        for package, files in declared.items():
            if len(files) > 1:
                problems[(package, tuple(sorted(files)))].add(host)

    if problems:
        print("packages declared more than once for a single host:\n", file=sys.stderr)
        for (package, files), hosts in sorted(problems.items()):
            print(f"  ✗ {package}  (on {', '.join(sorted(hosts))})", file=sys.stderr)
            for path in files:
                print(f"      {path}", file=sys.stderr)
        print(
            "\n  Pick one file to own each package and delete the others."
            "\n  Nix will not complain about this: the lists concatenate and the"
            "\n  closure is the same, so the copies simply drift apart.\n",
            file=sys.stderr,
        )
        return 1

    hosts = len(H.hosts())
    print(f"✓ no package reaches any of the {hosts} hosts from two declarations")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
