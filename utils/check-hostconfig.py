#!/usr/bin/env python3
"""Prove that `kz configure` cannot damage a host's config.nix.

This tool rewrites files that decide whether a machine boots. "It looked
right when I ran it" is not evidence — `kz create-host` shipped a generator
that produced perfectly readable Nix with an unbalanced brace, and nobody saw
it by eye. So the editor is checked the same way: against every real host in
the repo, plus the awkward shapes that do not exist here yet but will.

WHAT IS ASSERTED, AND WHY EACH ONE MATTERS

  parses            the result is fed to `nix-instantiate --parse`. A file
                    that does not parse takes the whole flake down.
  faithful          reading the result back yields exactly the bundles that
                    were asked for — no more, none missing.
  no duplicates     a name appears once. Nix tolerates a repeated list
                    element, so nothing would ever complain.
  complete          every bundle in the registry appears in the block, on or
                    off. This is what makes the file the menu.
  stable            rendering the result again changes nothing. Without this
                    every run grows the file — which it did, gluing a fresh
                    section heading on each pass, until this check caught it.
  preserves         everything outside the block survives byte for byte, and
                    notes written about the machine come back attached to the
                    bundle they annotated.
  order-blind       two hosts that end up with the same bundles end up with
                    the same block, whatever order they listed them in.

Run from the repo root:  python3 utils/check-hostconfig.py
Also wired into pre-commit.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "utils" / "lib"))

import hostconfig as H  # noqa: E402

FAILURES: list[str] = []


def check(condition: bool, message: str) -> bool:
    if not condition:
        FAILURES.append(message)
    return condition


def scratch(text: str) -> Path:
    path = Path(tempfile.mkdtemp(prefix="kz-hostconfig-")) / "config.nix"
    path.write_text(text)
    return path


def parses(text: str) -> tuple[bool, str]:
    if shutil.which("nix-instantiate") is None:
        return True, ""
    path = scratch(text)
    proc = subprocess.run(
        ["nix-instantiate", "--parse", str(path)], capture_output=True, text=True
    )
    return proc.returncode == 0, proc.stderr.strip()


def outside_block(config: H.HostConfig) -> list[str]:
    """Every line of the file that is not part of the bundles block."""
    if not config.has_block:
        return list(config.lines)
    return config.lines[: config.start] + config.lines[config.end + 1 :]


def render_case(
    label: str,
    source: str,
    selection: set[str],
    locale: str | None,
    kernel: str | None = None,
) -> str:
    """Render one edit and assert everything that must hold of the result."""
    original = H.parse(scratch(source))
    text = H.render(original, selection, locale=locale, kernel=kernel)

    valid, error = parses(text)
    check(valid, f"{label}: result does not parse as Nix — {error}")

    for problem in H.verify(text, selection, locale, kernel):
        FAILURES.append(f"{label}: {problem}")

    result = H.parse(scratch(text))

    names = [e.name for e in result.entries]
    check(
        len(names) == len(set(names)),
        f"{label}: a bundle is listed more than once",
    )

    registry = {b["name"] for b in H.catalogue()}
    check(
        registry <= set(names),
        f"{label}: missing from the block: {sorted(registry - set(names))}",
    )

    again = H.render(result, result.enabled, locale=result.locale, kernel=result.kernel)
    check(again == text, f"{label}: rendering is not stable — a second run changes the file")

    # Everything the block does not own must survive untouched.
    before = outside_block(original)
    after = outside_block(result)
    if (
        original.has_block
        and locale == original.locale
        and (kernel is None or kernel == original.kernel)
    ):
        check(
            before == after,
            f"{label}: text outside the bundles block changed",
        )

    return text


def check_real_hosts() -> None:
    """Every host in the repo, left as it is and then edited."""
    for host in H.hosts():
        source = H.path_for(host).read_text()
        config = H.parse(H.path_for(host))
        current = config.enabled

        render_case(f"{host} unchanged", source, current, config.locale)
        render_case(f"{host} +desktop-gis", source, current | {"desktop-gis"}, config.locale)
        render_case(f"{host} -base", source, current - {"base"}, config.locale)
        render_case(f"{host} emptied", source, set(), config.locale)
        render_case(
            f"{host} everything",
            source,
            {b["name"] for b in H.catalogue()},
            config.locale,
        )


def check_notes_survive() -> None:
    """A note about *this machine* must come back attached to its bundle."""
    note = "This laptop's Wi-Fi firmware needs the bluetooth module loaded first."
    source = (
        "{\n"
        "  bundles = [\n"
        f"    # {note}\n"
        '    "services-device"\n'
        "  ];\n"
        "}\n"
    )
    text = render_case("note preservation", source, {"services-device", "base"}, None)
    check(note in text, "note preservation: the host's own comment was dropped")

    # And it must not multiply on the way back through.
    second = H.render(H.parse(scratch(text)), {"services-device", "base"}, locale=None)
    check(
        second.count(note) == 1,
        f"note preservation: the comment appears {second.count(note)} times after a second pass",
    )


def check_inline_comment_survives() -> None:
    source = (
        "{\n"
        "  bundles = [\n"
        '    "base" # the machine boots from ZFS\n'
        "  ];\n"
        "}\n"
    )
    text = render_case("inline comment", source, {"base"}, None)
    check(
        "the machine boots from ZFS" in text,
        "inline comment: a trailing comment on a bundle line was dropped",
    )


def check_duplicates_collapse() -> None:
    source = (
        "{\n"
        "  bundles = [\n"
        '    "base"\n'
        '    "base"\n'
        '    "desktop-browsers"\n'
        '    "base"\n'
        "  ];\n"
        "}\n"
    )
    config = H.parse(scratch(source))
    check(
        config.enabled == {"base", "desktop-browsers"},
        "duplicates: reading a repeated name did not collapse it",
    )
    render_case("duplicates", source, config.enabled, None)


def check_order_does_not_matter() -> None:
    """Two hosts with the same bundles get the same block, however they listed them."""
    forwards = '{\n  bundles = [\n    "base"\n    "security"\n    "terminal-ai"\n  ];\n}\n'
    backwards = '{\n  bundles = [\n    "terminal-ai"\n    "security"\n    "base"\n  ];\n}\n'
    selection = {"base", "security", "terminal-ai"}
    a = render_case("order forwards", forwards, selection, None)
    b = render_case("order backwards", backwards, selection, None)
    check(a == b, "order: the same selection rendered two different files")


def check_single_line_block() -> None:
    source = '{\n  bundles = [ "base" "security" ];\n}\n'
    config = H.parse(scratch(source))
    check(
        config.enabled == {"base", "security"},
        "single line: a one-line bundles list was not read",
    )
    render_case("single line", source, config.enabled, None)


def check_no_block_at_all() -> None:
    source = "{\n  # Nothing here yet.\n  nixosStateVersion = \"25.05\";\n}\n"
    config = H.parse(scratch(source))
    check(not config.has_block, "no block: a file without a bundles list looked like it had one")
    text = render_case("no block", source, {"base"}, "za-en")
    check(
        'nixosStateVersion = "25.05";' in text,
        "no block: an unrelated key was lost when the block was inserted",
    )
    check('locale = "za-en";' in text, "no block: the locale was not written")


def check_unknown_name_is_kept() -> None:
    """A name that is not a bundle is an eval error. Comment it, do not delete it."""
    source = '{\n  bundles = [\n    "base"\n    "desktop-reading"\n  ];\n}\n'
    config = H.parse(scratch(source))
    check(
        config.unknown == ["desktop-reading"],
        f"unknown name: not reported, got {config.unknown}",
    )
    text = H.render(config, config.enabled, locale=None)
    check(
        '# "desktop-reading"' in text,
        "unknown name: dropped from the file instead of being commented out",
    )
    valid, error = parses(text)
    check(valid, f"unknown name: result does not parse — {error}")


def check_locale_round_trip() -> None:
    source = '{\n  bundles = [ "base" ];\n  locale = "pt-en";\n}\n'
    text = render_case("locale change", source, {"base"}, "ke-en")
    check('locale = "ke-en";' in text, "locale: the new value was not written")
    check('"pt-en"' not in text, "locale: the old value is still in the file")


def check_kernel_round_trip() -> None:
    """The kernel key must behave exactly as the locale key does.

    Same three properties: the new value lands, the old one goes, and a host
    that has never named a kernel is not given one just for being rendered —
    otherwise every config.nix in the fleet grows a line on the next run.
    """
    source = '{\n  bundles = [ "base" ];\n  kernel = "stable";\n}\n'
    text = render_case("kernel change", source, {"base"}, None, "latest")
    check('kernel = "latest";' in text, "kernel: the new value was not written")
    check('"stable"' not in text, "kernel: the old value is still in the file")

    bare = '{\n  bundles = [ "base" ];\n}\n'
    untouched = render_case("kernel absent", bare, {"base"}, None, None)
    # Match the assignment, not the bare word: several bundle descriptions
    # in the rendered block mention kernels (services-system does "kernel
    # hardening"), and a substring test reads those as a written key.
    check(
        not re.search(r"^\s*kernel\s*=", untouched, re.M),
        "kernel: a host that named no kernel was given one anyway",
    )

    added = render_case("kernel added", bare, {"base"}, None, "latest")
    check('kernel = "latest";' in added, "kernel: was not added to a file lacking it")
    valid, error = parses(added)
    check(valid, f"kernel: adding the key produced unparseable Nix — {error}")


def check_generated_host_is_already_canonical() -> None:
    """`kz create-host` and `kz configure` must agree on the shape of a file.

    They share a renderer precisely so that the first `kz configure` on a
    freshly created host is a one-line diff rather than a wholesale reformat.
    If that ever stops being true, the two have grown separate opinions.
    """
    generated = subprocess.run(
        [
            sys.executable,
            str(ROOT / "utils" / "gen-host-config.py"),
            "checkbox",
            "--locale",
            "za-en",
            "--laptop",
        ],
        capture_output=True,
        text=True,
    )
    if not check(generated.returncode == 0, f"gen-host-config failed: {generated.stderr}"):
        return

    config = H.parse(scratch(generated.stdout))
    again = H.render(config, config.enabled, locale=config.locale)
    check(
        again == generated.stdout,
        "generated host: kz configure would reformat a file kz create-host just wrote",
    )
    valid, error = parses(generated.stdout)
    check(valid, f"generated host: does not parse — {error}")


def check_menu_labels_have_no_commas() -> None:
    """The bug that made a fully configured host look empty.

    `gum choose --selected` takes ONE comma-separated string. A label with a
    comma in it is split into fragments matching no option, so the bundle
    fails to pre-tick — and abyss, which takes 26 of 29 bundles, opened
    showing almost everything switched off. Nothing crashed; the tool simply
    misreported the machine, which is worse.
    """
    sys.path.insert(0, str(ROOT / "utils"))
    import configure as C

    known = {b["name"] for b in H.catalogue()}
    for bundle in H.catalogue():
        label = C.label_for(bundle, 100)
        check(
            "," not in label,
            f"menu label for {bundle['name']} contains a comma: {label!r}",
        )
        check(
            C.name_from_label(label, known) == bundle["name"],
            f"menu label for {bundle['name']} does not read back: {label!r}",
        )

    labels = [C.label_for(b, 100) for b in H.catalogue()]
    check(len(labels) == len(set(labels)), "two bundles produce the same menu label")


def check_catalogue_nests() -> None:
    """A child must sit immediately under its parent, or the menu is a lie."""
    order = H.catalogue()
    position = {b["name"]: i for i, b in enumerate(order)}
    paths = {b["path"] for b in order}
    for bundle in order:
        parent = H.parent_path(bundle["path"], paths)
        if parent is None:
            check(bundle["depth"] == 0, f"{bundle['name']}: depth without a parent")
            continue
        parent_name = next(b["name"] for b in order if b["path"] == parent)
        check(
            position[parent_name] < position[bundle["name"]],
            f"{bundle['name']} is listed above its parent {parent_name}",
        )
        check(bundle["depth"] > 0, f"{bundle['name']}: nested but shown at depth 0")


def check_cascade() -> None:
    """Switching a parent on brings its children — except the opt-in ones."""
    got, why = H.cascade({"services-device"})
    check(
        "services-device-input" in got,
        "cascade: a child was not brought in by its parent",
    )
    check(
        why.get("services-device-input") == "services-device",
        "cascade: did not record which parent brought a child",
    )
    check(
        "services-device-peripherals" not in got,
        "cascade: an opt-in bundle was added on the host's behalf. "
        "biometrics can decide whether the owner can log in.",
    )
    check(
        H.opt_in("services-device-peripherals") is not None,
        "cascade: services-device-peripherals lost its optIn marker",
    )
    check(
        "desktop-gis-source-builds" not in H.cascade({"desktop-gis"})[0],
        "cascade: source builds were added on the host's behalf — hours of compilation",
    )
    check(H.opt_in("services-device") is None, "cascade: a plain bundle reads as opt-in")

    # Asking for an opt-in bundle by name must still work.
    named, _ = H.cascade({"services-device", "services-device-peripherals"})
    check(
        "services-device-peripherals" in named,
        "cascade: an explicitly named opt-in bundle was dropped",
    )


def check_dropping_a_parent_drops_its_children() -> None:
    """A removal that `implies` immediately undoes is a lie, not a removal.

    Every child bundle names its parent in `implies`, so a host that keeps
    `services-device-input` gets `services-device` whatever its config.nix
    says. Before this rule the tool printed "- services-device" and, three
    lines later, "also brought in, because something you picked needs it:
    services-device" — reporting a change it had already undone.
    """
    for parent in ("services-device", "services-system", "desktop-gis"):
        kids = H.children_of(parent)
        check(bool(kids), f"cascade-off: {parent} has no children to test with")
        swept, why = H.cascade_off({parent})
        for kid in kids:
            check(
                kid in swept,
                f"cascade-off: {kid} survived {parent} being dropped, and would "
                f"drag it back through implies",
            )
            check(
                why.get(kid) == parent,
                f"cascade-off: did not record that {kid} went with {parent}",
            )

    # optIn means "never added for you", not "never removed". A group being
    # dropped must not leave its parts stranded.
    swept, _ = H.cascade_off({"services-device"})
    check(
        "services-device-peripherals" in swept,
        "cascade-off: an opt-in child was stranded by its parent's removal",
    )

    # And the contradiction detector itself.
    back = H.resurrected({"services-device-input"}, {"services-device"})
    check(
        back.get("services-device") == ["services-device-input"],
        f"resurrected: did not spot the parent coming back — {back}",
    )
    check(
        H.resurrected({"base"}, {"desktop-gis"}) == {},
        "resurrected: reported a bundle as returning when nothing implies it",
    )


def check_required_cannot_be_removed() -> None:
    """A required bundle must survive an edit that tries to drop it.

    `base` carries the bootloader. Unticking it is one keystroke and the
    result builds perfectly well, then does not boot — discovered at a
    console, on a machine that no longer has an ssh daemon either.
    """
    refused = H.removals_refused({"base", "services-system", "desktop-gis"}, {"desktop-gis"})
    check("base" in refused, "required: removing base was not refused")
    check(
        "services-system" in refused,
        "required: removing services-system was not refused",
    )
    check(
        "desktop-gis" not in refused,
        "required: an ordinary bundle was treated as required",
    )
    check(
        bool(refused.get("base")),
        "required: base was refused without saying why",
    )

    # Not the same as "every host must have it". bay takes neither and must
    # not be made to: it imports its software directly.
    bay = H.parse(H.path_for("bay"))
    check(
        "base" not in bay.enabled,
        "required: this test assumes bay does not take base; it now does",
    )
    check(
        H.removals_refused(bay.enabled, bay.enabled | {"desktop-comms"}) == {},
        "required: adding a bundle to a host without base was refused",
    )


def check_package_reader() -> None:
    """The preview pane must show what a bundle installs, not an empty list.

    The first version of the reader returned nothing for `desktop-browsers` —
    a module whose entire content is four browsers. `with pkgs;` puts a
    semicolon at bracket depth zero and the scanner stopped on it. An empty
    preview looks like a bundle that installs nothing, which is a worse
    answer than no preview at all.
    """
    sys.path.insert(0, str(ROOT / "utils" / "lib"))
    import bundleinfo as I

    index = {b["name"]: b for b in H.catalogue()}

    browsers = I.summarise(index["desktop-browsers"])["packages"]
    for expected in ("firefox", "brave", "google-chrome"):
        check(
            expected in browsers,
            f"package reader: desktop-browsers does not list {expected} — got {browsers}",
        )

    # base/fish.nix turns the fleet's login shell on through the nested
    # `programs.fish = { enable = true; … }` form, which the flat regex missed.
    fish = I.packages_in(ROOT / "software" / "base" / "fish.nix")
    check("programs.fish" in fish[1], f"package reader: fish.nix reads as enabling nothing: {fish[1]}")

    # Comments inside a list name other packages; reading them would report
    # software the module does not install.
    check(
        "File" not in browsers and "manager" not in browsers,
        f"package reader: comment text was read as a package — {browsers}",
    )

    # Shell scripts embedded in indented strings are not package lists. The
    # reader offered HOME, chmod, CYAN and a row of underscores until it
    # learned to walk list ELEMENTS rather than scan text for identifiers.
    everything = {p for b in H.catalogue() for p in I.summarise(b)["packages"]}
    for bogus in ("HOME", "chmod", "clear", "complete", "CYAN", "Ctrl", "USER"):
        check(
            bogus not in everything,
            f"package reader: {bogus!r} is a word from an embedded shell script, "
            "not a package",
        )
    for name in everything:
        check(
            not name.startswith(".") and not name.endswith("."),
            f"package reader: {name!r} is a fragment of an attribute path",
        )
        check(
            name.split(".")[0] not in I.NAMING_BUILDERS,
            f"package reader: {name!r} is a builder, not the package it builds",
        )

    # A builder call contributes the name it builds, not the builder.
    tuis = I.summarise(index["terminal-tuis"])["packages"]
    check(bool(tuis), "package reader: terminal-tuis lists no packages at all")

    # The bottom pane looks descriptions up here; if the index disappears the
    # pane must degrade, not crash.
    sys.path.insert(0, str(ROOT / "utils" / "lib"))
    index_path = ROOT / "docs" / "references" / "software.json"
    if index_path.exists():
        import json

        catalogue_index = json.loads(index_path.read_text())
        described = sum(1 for p in everything if p in catalogue_index)
        check(
            described >= len(everything) // 2,
            f"package reader: only {described}/{len(everything)} packages resolve "
            "against docs/references/software.json",
        )

    # Nothing may crash, and coverage must not silently collapse.
    modules = unread = 0
    for bundle in H.catalogue():
        info = I.summarise(bundle)
        modules += len(info["modules"])
        unread += len(info["unread"])
        check(
            isinstance(info["packages"], list),
            f"package reader: {bundle['name']} produced no package list",
        )
    read = modules - unread
    check(
        read >= int(modules * 0.7),
        f"package reader: only {read}/{modules} modules could be read; "
        "something regressed in the parser",
    )


def check_filter() -> None:
    """`/` must find a bundle by the software in it, not just by its name."""
    sys.path.insert(0, str(ROOT / "utils" / "lib"))
    import bundleinfo as I

    catalogue = H.catalogue()

    def hits(query: str) -> list[str]:
        return [b["name"] for b in catalogue if I.matches(b, query)]

    for query, expected in (
        ("firefox", "desktop-browsers"),
        ("qgis", "desktop-gis"),
        ("sanoid", "services-system-storage"),
        # obs.nix installs through `pkgs.wrapOBS`, so there is no bare
        # package name to match — the module filename carries it.
        ("obs", "desktop-multimedia"),
    ):
        found = hits(query)
        check(
            expected in found,
            f"filter: /{query} does not find {expected} — got {found}",
        )

    check(
        hits("") == [b["name"] for b in catalogue],
        "filter: an empty query hid something",
    )
    check(hits("zzzznotathing") == [], "filter: a nonsense query matched something")
    check(
        I.matches(catalogue[0], "  FIREFOX  ") == I.matches(catalogue[0], "firefox"),
        "filter: queries are not case- and space-insensitive",
    )


def check_module_editor() -> None:
    """Editing a shared module must be surgical, or refuse outright.

    A host file is one machine. A module under software/ is every host taking
    the bundle — nine, today — so the editor locates a package by parsing and
    declines anything it cannot do cleanly.
    """
    import shutil as _shutil
    import tempfile as _tempfile

    sys.path.insert(0, str(ROOT / "utils" / "lib"))
    import bundleinfo as I
    import moduleedit as M

    def scratch_module(source: Path) -> Path:
        target = Path(_tempfile.mkdtemp()) / source.name
        _shutil.copy(source, target)
        return target

    browsers = scratch_module(ROOT / "software" / "desktop" / "browsers" / "browsers.nix")
    original = browsers.read_text()

    # Remove.
    text = M.remove(browsers, "brave")
    check("brave" not in text, "module editor: brave survived removal")
    for kept in ("firefox", "google-chrome", "ungoogled-chromium"):
        check(kept in text, f"module editor: removing brave also lost {kept}")
    check(M.parses(text)[0], "module editor: removal produced unparseable Nix")
    check(
        M.verify(browsers, text, {"firefox", "google-chrome", "ungoogled-chromium"}) == [],
        "module editor: the result does not read back as asked",
    )

    # Add, in sorted position because that list is sorted.
    text = M.add(browsers, "chromium")
    order = [
        line.strip()
        for line in text.split("\n")
        if line.strip() in {"brave", "chromium", "firefox"}
    ]
    check(
        order == sorted(order),
        f"module editor: addition broke the list's sorted order — {order}",
    )

    # Composing edits must not touch the file until everything has passed.
    M.rendered(browsers, {"firefox"})
    check(
        browsers.read_text() == original,
        "module editor: the module was written to while the edit was still "
        "being composed. A refusal partway would leave it half-edited.",
    )

    # Refusals.
    for package, why in (
        ("definitely-not-here", "a package that is not in the module"),
        ("firefox nonsense", "a name that is not an attribute"),
    ):
        try:
            M.add(browsers, package)
            M.remove(browsers, package)
            check(False, f"module editor: accepted {why}")
        except M.Refused:
            pass

    try:
        M.add(browsers, "firefox")
        check(False, "module editor: added a package the module already has")
    except M.Refused:
        pass

    # A name in a comment or an embedded shell script is not an entry. This
    # is what makes the editor safe to point at any module in the tree.
    fish = ROOT / "software" / "base" / "fish.nix"
    if fish.exists():
        names = {e.name for e in M.entries(fish)}
        for bogus in ("source", "alias", "set", "function"):
            check(
                bogus not in names,
                f"module editor: {bogus!r} in fish.nix was read as a package entry",
            )

    # Every module in the tree must be analysable without blowing up.
    for bundle in H.catalogue():
        for module in bundle.get("modules", []):
            path = ROOT / "software" / bundle["path"] / module
            if not path.exists():
                continue
            try:
                found = M.entries(path)
            except Exception as exc:  # noqa: BLE001
                check(False, f"module editor: {module} could not be analysed — {exc}")
                continue
            for entry in found:
                check(
                    entry.name in set(I.packages_in(path)[0]),
                    f"module editor: {module} reports an entry {entry.name!r} that "
                    "the package reader does not know about",
                )

    # Some packages are load-bearing the way `base` is load-bearing for a
    # host: fish is somebody's login shell, and the rest are what fish's own
    # interactiveShellInit invokes on every interactive start.
    fish_module = ROOT / "software" / "base" / "fish.nix"
    if fish_module.exists():
        for locked in ("fish", "starship", "fzf", "zoxide", "direnv", "atuin"):
            check(
                M.required_package(fish_module, locked) is not None,
                f"module editor: {locked} is not marked required in base",
            )
            try:
                M.remove(fish_module, locked)
                check(False, f"module editor: {locked} was removable from fish.nix")
            except M.Refused:
                pass
        check(
            M.required_package(fish_module, "bat") is None,
            "module editor: an ordinary package reads as required",
        )
        check(
            M.bundle_for(fish_module)["name"] == "base",
            "module editor: could not work out which bundle owns fish.nix",
        )

    # Packages this flake DEFINES are locked from deletion, though the
    # bundles holding them stay optional. Removing the entry that installs
    # one does not free anything — the derivation stays, built by nothing and
    # reaching no machine.
    overlay = M.overlay_packages()
    for ours in ("kartoza-timesheet", "kartoza-screencaster", "gatus-monitor",
                 "claude-sandboxed", "llm-sandboxed", "zfs-backup"):
        check(ours in overlay, f"module editor: {ours} not recognised as ours")
    check(
        "signal-desktop" not in overlay,
        "module editor: a patched nixpkgs package was claimed as ours — it is "
        "still in nixpkgs if the entry goes, so it is not locked",
    )
    check(
        "firefox" not in overlay,
        "module editor: a plain nixpkgs package was claimed as ours",
    )

    for path, package in (
        ("software/desktop/kartoza-apps/kartoza-timesheet.nix", "kartoza-timesheet"),
        ("software/terminal/ai/claude-code.nix", "claude-sandboxed"),
        # Built in the module's own let block, a few lines above the list.
        ("software/desktop/environments/cosmic/extensions/extensions.nix",
         "cosmic-ext-enroll"),
        ("software/desktop/environments/cosmic/packages.nix", "screenshot-satty"),
    ):
        target = ROOT / path
        if not target.exists():
            continue
        check(
            M.required_package(target, package) is not None,
            f"module editor: {package} is deletable, but this flake defines it",
        )
        try:
            M.remove(target, package)
            check(False, f"module editor: removed {package}, which this flake defines")
        except M.Refused:
            pass

    browsers_locked = M.required_package(browsers, "firefox")
    check(
        browsers_locked is None,
        f"module editor: firefox reads as locked — {browsers_locked}",
    )

    # A brand-new bundle starts with an empty list, so "no entries yet" has
    # to mean "insert the first one" rather than a refusal.
    made = None
    try:
        made = M.create_bundle("desktop/kz-selftest", "Scratch bundle for the test suite.")
        module = made / "kz-selftest.nix"
        text = M.add(module, "ardour")
        module.write_text(text)
        text = M.add(module, "carla")
        check(M.parses(text)[0], "module editor: a new bundle's module does not parse")
        check(
            M.verify(module, text, {"ardour", "carla"}) == [],
            "module editor: adding to an empty list did not read back",
        )
        nested = M.create_bundle("desktop/kz-selftest/deep", "Nested scratch bundle.")
        import json as _json

        implies = _json.loads((nested / "bundle.json").read_text())["implies"]
        check(
            "desktop-kz-selftest" in implies,
            f"module editor: a nested bundle does not imply its parent — {implies}",
        )
        try:
            M.create_bundle("desktop/kz-selftest", "again")
            check(False, "module editor: re-created a bundle that already exists")
        except M.Refused:
            pass
        try:
            M.create_bundle("desktop/Not Valid", "bad name")
            check(False, "module editor: accepted an unusable directory name")
        except M.Refused:
            pass
    finally:
        if made is not None:
            _shutil.rmtree(made, ignore_errors=True)

    # And the host-reach calculation the operator is shown before agreeing.
    reach = M.hosts_using("desktop-browsers")
    check(
        "abyss" in reach,
        f"module editor: abyss missing from the hosts using desktop-browsers — {reach}",
    )
    check(
        M.hosts_using("desktop-gis-source-builds") != H.hosts(),
        "module editor: an opt-in bundle is reported as reaching every host",
    )


def check_cursor_restore() -> None:
    """Editing must not send the cursor back to the top of the list.

    Deleting a package rebuilds the right pane, and a rebuild that does not
    restore the position means removing three packages from one module costs
    two scrolls back down. Skipped when Textual is absent — this is the only
    check that needs it, and the command falls back to the gum picker there.
    """
    sys.path.insert(0, str(ROOT / "utils" / "lib"))
    try:
        import configure_tui as T
    except ImportError:
        return

    class Row:
        def __init__(self, disabled: bool) -> None:
            self.disabled = disabled

    # Module headings are disabled rows; a restored position can land on one.
    rows = [Row(True), Row(False), Row(False), Row(True), Row(False)]
    for at, expected in ((0, 1), (1, 1), (2, 2), (3, 2), (4, 4)):
        got = T._nearest_selectable(rows, at)
        check(
            got == expected,
            f"cursor: restoring to {at} gave {got}, expected {expected}",
        )
    for at in range(len(rows)):
        check(
            not rows[T._nearest_selectable(rows, at)].disabled,
            f"cursor: restoring to {at} landed on a disabled row",
        )


def check_module_edits_are_not_discarded() -> None:
    """A package deletion must survive a host whose bundle list did not change.

    The save path used to ask only "did config.nix change?" — so deleting a
    package without also toggling a bundle hit "nothing to write" and threw
    the edit away, having reported nothing. The module looked edited until it
    was opened again.
    """
    sys.path.insert(0, str(ROOT / "utils"))
    import configure as C

    module = ROOT / "software" / "desktop" / "browsers" / "browsers.nix"

    check(
        C.nothing_to_do(host_changed=False, module_edits={}),
        "save: did not recognise that there is nothing to write",
    )
    check(
        not C.nothing_to_do(host_changed=True, module_edits={}),
        "save: a changed host file was treated as nothing to write",
    )
    check(
        not C.nothing_to_do(host_changed=False, module_edits={module: {"firefox"}}),
        "save: a package edit was discarded because the host file was unchanged",
    )
    check(
        not C.nothing_to_do(host_changed=True, module_edits={module: {"firefox"}}),
        "save: both kinds of change together were treated as nothing to write",
    )


def check_unfree_declarations() -> None:
    """A module using an unfree package must declare it, or it cannot be used.

    `services-device-peripherals` could not be enabled on any host:
    hp-scanner.nix pulls `hplipWithPlugin`, which is unfree and which
    `lib.getName` reports as "hplip", and nothing allowed that name. Every
    file parsed; the failure only appeared at `nixos-rebuild`. That is the
    whole argument for evaluating after a write rather than only parsing.
    """
    unfree_users = {
        "software/services/device/peripherals/hp-scanner.nix": "hplip",
        "software/desktop/games/retroarch.nix": "libretro-genesis-plus-gx",
    }
    for path, package in unfree_users.items():
        target = ROOT / path
        if not target.exists():
            continue
        text = target.read_text()
        check(
            "kartoza.unfreePackages" in text and package in text,
            f"unfree: {Path(path).name} uses an unfree package without declaring "
            f"{package!r} in kartoza.unfreePackages, so the bundle holding it "
            "cannot be enabled on any host",
        )


def check_evaluation_guard() -> None:
    """The write path must offer to undo itself when evaluation fails."""
    sys.path.insert(0, str(ROOT / "utils"))
    import configure as C

    for name in ("evaluates", "_put_back", "_evaluate_and_keep", "untracked_bundles"):
        check(hasattr(C, name), f"evaluation guard: configure.{name} is missing")

    # Putting files back is the part that must be exactly right.
    scratch_dir = Path(tempfile.mkdtemp())
    first, second = scratch_dir / "a.nix", scratch_dir / "b.nix"
    first.write_text("original a\n")
    second.write_text("original b\n")
    restore = {first: first.read_text(), second: second.read_text()}
    first.write_text("edited a\n")
    second.write_text("edited b\n")
    C._put_back(restore)
    check(first.read_text() == "original a\n", "evaluation guard: a file was not restored")
    check(second.read_text() == "original b\n", "evaluation guard: a file was not restored")


def check_default_host() -> None:
    """No host named means this machine, the way `kz update` resolves it."""
    sys.path.insert(0, str(ROOT / "utils"))
    import configure as C

    import os as _os

    short = _os.uname().nodename.split(".")[0]
    resolved = C.this_machine()
    if short in H.hosts():
        check(
            resolved == short,
            f"default host: this machine is {short}, a known host, but resolved "
            f"to {resolved!r}",
        )
    else:
        check(
            resolved is None,
            f"default host: {short} is not a host in hosts/, but resolved to "
            f"{resolved!r} — an unrelated machine would be edited",
        )

    # An FQDN must still match the directory name, as `hostname -s` does.
    check(
        "." not in (resolved or ""),
        f"default host: resolved to {resolved!r}, which is not a short name",
    )


def check_hash_in_string() -> None:
    """A `#` inside a string is not the start of a comment."""
    code, comment = H.split_comment('  name = "a#b"; # real comment')
    check(code == '  name = "a#b"; ', f"hash in string: split the wrong place, got {code!r}")
    check(comment == " real comment", f"hash in string: comment was {comment!r}")


def main() -> int:
    check_real_hosts()
    check_notes_survive()
    check_inline_comment_survives()
    check_duplicates_collapse()
    check_order_does_not_matter()
    check_single_line_block()
    check_no_block_at_all()
    check_unknown_name_is_kept()
    check_locale_round_trip()
    check_kernel_round_trip()
    check_generated_host_is_already_canonical()
    check_menu_labels_have_no_commas()
    check_catalogue_nests()
    check_cascade()
    check_dropping_a_parent_drops_its_children()
    check_required_cannot_be_removed()
    check_package_reader()
    check_filter()
    check_module_editor()
    check_cursor_restore()
    check_module_edits_are_not_discarded()
    check_unfree_declarations()
    check_evaluation_guard()
    check_default_host()
    check_hash_in_string()

    if FAILURES:
        print("hostconfig: the config.nix editor is not safe to run:\n", file=sys.stderr)
        for failure in FAILURES:
            print(f"  ✗ {failure}", file=sys.stderr)
        print(file=sys.stderr)
        return 1

    hosts = len(H.hosts())
    bundles = len(H.catalogue())
    print(f"hostconfig: ✓ {hosts} hosts × {bundles} bundles, every edit parses and round-trips")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
