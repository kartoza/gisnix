#!/usr/bin/env python3
"""Patch super-stt's Cargo.lock: drop duplicate [[package]] stanzas, and
add serde_json as a declared dependency of super-stt-cli.

Two unrelated fixes live here together because both are Cargo.lock
surgery and package.nix can only point cargoLock.lockFile at one
patched file (see its comment for why this can't be done via
postPatch instead).

pop-os/libcosmic.git's Cargo.lock lists build_helpers, cosmic-config,
cosmic-config-derive, iced_core, and iced_futures TWICE each: once sourced
via a bare `libcosmic.git#<rev>` URL, once via `libcosmic.git?rev=<rev>#<rev>`
— same commit, but Cargo's feature resolver treated them as two distinct
units (different enabled features -> different dependency lists), so they
got two separate lockfile entries sharing one name+version. nixpkgs'
cargoVendorDir can't place two entries under the same "<name>-<version>"
vendor slot (hits "Permission denied" on the second symlink). Since none
of this is ever compiled (super-stt-daemon/-cli, the only workspace
members this package actually builds, never reach libcosmic), which
variant survives doesn't matter functionally here — only that the
lockfile stays internally consistent after one is dropped.

Drops the bare-URL stanza for each of those five, then rewrites every
remaining disambiguated dependency reference to the bare URL (e.g.
cosmic-panel-config's dependency on cosmic-config) to point at the
?rev= form instead, since that's the only variant left.

See package.nix's cargoLock comment. Re-verify this logic against any
version bump: `grep -c 'libcosmic.git#' Cargo.lock` should be 0 after
this runs, and `grep -c 'libcosmic.git?rev=' Cargo.lock` should be
unchanged from before.
"""
import re
import sys

DUP_NAMES = {
    "build_helpers",
    "cosmic-config",
    "cosmic-config-derive",
    "iced_core",
    "iced_futures",
}
BARE_URL = "git+https://github.com/pop-os/libcosmic.git#"
QUERY_URL = "git+https://github.com/pop-os/libcosmic.git?rev="


def main():
    text = open(sys.argv[1]).read()
    blocks = text.split("[[package]]\n")
    header, stanzas = blocks[0], blocks[1:]

    kept = []
    dropped = []
    for stanza in stanzas:
        m = re.match(r'name = "([^"]+)"\n', stanza)
        name = m.group(1) if m else None
        fields = stanza.split("\n\n", 1)[0]
        is_bare_dup = (
            name in DUP_NAMES
            and BARE_URL in fields
            and "?rev=" not in fields
        )
        if is_bare_dup:
            dropped.append(name)
        else:
            kept.append(stanza)

    missing = DUP_NAMES - set(dropped)
    if missing:
        print(
            f"dedupe-cargo-lock.py: expected to drop a bare-URL stanza for "
            f"{sorted(missing)} but found none — Cargo.lock has drifted, "
            f"re-check this script against the new lockfile.",
            file=sys.stderr,
        )
        sys.exit(1)

    out = header + "[[package]]\n" + "[[package]]\n".join(kept)
    # Only the bare *disambiguator* form (no trailing #rev fragment)
    # appears in dependency lists; rewrite it to the query form so
    # surviving references (e.g. cosmic-panel-config -> cosmic-config)
    # don't dangle now that the bare stanza is gone. The rev is the same
    # 40-char commit both forms already pinned to.
    rev = None
    rev_match = re.search(re.escape(QUERY_URL) + r"([0-9a-f]{40})#", text)
    if rev_match:
        rev = rev_match.group(1)
    if rev is None:
        print("dedupe-cargo-lock.py: couldn't find the query-form rev to rewrite to", file=sys.stderr)
        sys.exit(1)
    out = out.replace(
        "(git+https://github.com/pop-os/libcosmic.git)",
        f"(git+https://github.com/pop-os/libcosmic.git?rev={rev})",
    )

    # provision-model (super-stt-cli/src/main.rs, added via
    # super-stt-cli-provision.patch) needs serde_json directly — it's
    # only available transitively today, via super-stt-shared, which
    # Rust doesn't let a crate `use` by path. Cargo.toml gets the
    # matching `serde_json.workspace = true` line via postPatch
    # (package.nix); this is Cargo.lock's side of the same addition.
    cli_pattern = (
        r'(name = "super-stt-cli"\nversion = "[^"]*"\ndependencies = \[\n'
        r'(?:.*\n)*? "clap",\n)'
    )
    out, n = re.subn(cli_pattern, r'\1 "serde_json",\n', out, count=1)
    if n != 1:
        print(
            "dedupe-cargo-lock.py: couldn't find super-stt-cli's dependency "
            "list to add serde_json to — Cargo.lock has drifted, re-check "
            "this script against the new lockfile.",
            file=sys.stderr,
        )
        sys.exit(1)

    sys.stdout.write(out)


if __name__ == "__main__":
    main()
