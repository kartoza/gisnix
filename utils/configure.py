#!/usr/bin/env python3
"""`gisnix configure` — turn a host's software bundles on and off.

The list you tick comes from the bundle registry (`software/**/bundle.json`),
not from whatever the host's `config.nix` happens to mention today. That is
the point: a bundle added this morning is on the menu this afternoon, and a
host that never heard of it says so explicitly instead of by omission.

WHAT IT WILL NOT DO

  * write a name that is not a bundle — the selection is checked against the
    registry before anything is rendered
  * list a bundle twice, or leave the list in a random order — the block is
    rendered from a set in the registry's own order, so the file that comes
    out of a nine-bundle host and the file that comes out of a two-bundle
    host have the same shape
  * lose a comment somebody wrote about *this machine* — see
    `utils/lib/hostconfig.py` for how those are recovered and put back
  * leave a file that does not parse — the result is fed to
    `nix-instantiate --parse` and read back with the same parser that read
    the original, and the write is abandoned if either disagrees
  * write anything at all without showing you the diff first

Invoked through `utils/configure.sh`, which is what the command manifest
wraps. Run it directly for the same behaviour.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))

import hostconfig as H  # noqa: E402
import moduleedit as M  # noqa: E402


def _rel(path: Path) -> str:
    """Display path relative to whichever root it actually lives under —
    GISNIX_ROOT for a software/ module, TARGET_ROOT for a host's own
    config.nix. The two are the same directory when this runs inside
    gisnix's own checkout (all of history until now); a downstream
    consumer is the first case where they differ, so a plain single
    `.relative_to(H.REPO_ROOT)` would raise ValueError for a host path."""
    for root in (H.TARGET_ROOT, H.GISNIX_ROOT):
        try:
            return str(path.relative_to(root))
        except ValueError:
            continue
    return str(path)


GREEN = "\033[38;2;88;150;50m"
YELLOW = "\033[38;2;240;230;74m"
BLUE = "\033[38;2;147;176;35m"
RED = "\033[38;2;200;70;60m"
DIM = "\033[2m"
BOLD = "\033[1m"
NC = "\033[0m"

#: Gap between a label's name and its summary. Two spaces minimum, because
#: that gap is what `name_from_label` splits on to recover the bundle name
#: from what gum hands back.
NAME_GAP = 2


def name_column() -> int:
    """Column the summary starts in, measured rather than guessed.

    Hard-coding 30 worked until `services-device-peripherals` acquired a tree
    prefix and reached 31, at which point its label had no gap left and the
    name could not be read back out of it. Deriving the width from the
    longest name there actually is cannot go stale that way.
    """
    return max(len(_name_cell(b)) for b in H.catalogue()) + NAME_GAP


def _name_cell(bundle: dict) -> str:
    return f"{'  └ ' if bundle.get('depth') else ''}{bundle['name']}"


# ── presentation ──────────────────────────────────────────────────────────


def has_gum() -> bool:
    return shutil.which("gum") is not None


def interactive() -> bool:
    return sys.stdin.isatty() and sys.stdout.isatty()


def say(text: str = "") -> None:
    print(text)


def ok(text: str) -> None:
    print(f"  {GREEN}✓{NC} {text}")


def warn(text: str) -> None:
    print(f"  {YELLOW}!{NC} {text}")


def die(text: str) -> None:
    print(f"  {RED}✗{NC} {text}", file=sys.stderr)
    raise SystemExit(1)


def heading(text: str) -> None:
    print(f"\n  {BOLD}{text}{NC}")
    print(f"  {DIM}{'─' * 72}{NC}")


def gum(*args: str, stdin: str | None = None) -> str:
    """Run gum, returning its stdout.

    gum draws on the terminal, so its stdin and stderr are inherited rather
    than captured. A non-zero exit means the user pressed escape, which is a
    cancellation and not an error.
    """
    proc = subprocess.run(
        ["gum", *args],
        input=stdin,
        capture_output=False,
        stdout=subprocess.PIPE,
        text=True,
    )
    if proc.returncode != 0:
        die("cancelled — nothing was written")
    return proc.stdout.rstrip("\n")


def confirm(prompt: str, *, assume_yes: bool) -> bool:
    if assume_yes:
        return True
    if has_gum():
        return subprocess.run(["gum", "confirm", "--", prompt]).returncode == 0
    answer = input(f"  {prompt} [y/N] ").strip().lower()
    return answer in {"y", "yes"}


def rows() -> int:
    try:
        return os.get_terminal_size().lines
    except OSError:
        return 24


def columns() -> int:
    try:
        return os.get_terminal_size().columns
    except OSError:
        return 100


# ── choosing ──────────────────────────────────────────────────────────────


def label_for(bundle: dict, width: int) -> str:
    """`  └ services-device-input      Keyboards and mice…`

    A LABEL MUST NOT CONTAIN A COMMA. `gum choose --selected` takes one
    comma-separated string, so a label with a comma in it is split into
    fragments that match no option — and the bundle silently fails to
    pre-tick. Every bundle a host already had then appeared switched off,
    which is not a cosmetic bug: it is the tool misreporting the machine.

    So the summary is cut at its first comma, marked with an ellipsis like
    any other truncation. The full description is a line away in the state
    listing printed just above, and in `gisnix bundles <name>`.
    """
    name = _name_cell(bundle)
    column = name_column()
    room = max(20, width - column - 6)

    summary = " ".join(bundle["description"].split())
    if bundle.get("required"):
        summary = "required — " + summary
    elif bundle.get("optIn") and "pt-in" not in summary.split(",")[0]:
        # Some descriptions already open with "Opt-in:". Prefixing those
        # gives "opt-in — … Opt-in: …", which reads as a stutter.
        summary = "opt-in — " + summary
    cut = summary.split(",")[0]
    if len(cut) > room:
        cut = cut[: room - 1].rsplit(" ", 1)[0] + "…"
    elif cut != summary:
        cut += "…"
    return f"{name:<{column}}{cut}"


def name_from_label(label: str, known: set[str]) -> str | None:
    candidate = re.split(r"\s{2,}", label.strip(), maxsplit=1)[0].strip()
    candidate = candidate.removeprefix("└ ").strip()
    if candidate in known:
        return candidate
    first = candidate.split(" ", 1)[0]
    return first if first in known else None


def this_machine() -> str | None:
    """This host's name, if it is one of the fleet's.

    `hostname -s`, the way `gisnix update` resolves it — the short name, because
    a machine reporting an FQDN would otherwise never match a directory under
    hosts/.
    """
    name = os.uname().nodename.split(".")[0]
    return name if name in H.hosts() else None


def choose_host(default: str | None) -> str:
    available = H.hosts()
    if not available:
        die("no hosts under hosts/ carry a config.nix")
    if not has_gum():
        say("  hosts: " + ", ".join(available))
        answer = input(f"  which host? [{default or available[0]}] ").strip()
        return answer or default or available[0]
    args = [
        "choose",
        "--header",
        "Which host? (↑↓ to move, enter to pick)",
        "--height",
        str(min(len(available) + 2, max(6, rows() - 6))),
    ]
    if default in available:
        args += ["--selected", default]
    return gum(*args, "--", *available)


#: Returned when the two-pane chooser is not usable, as distinct from the
#: operator cancelling — one falls back, the other stops.
UNAVAILABLE = object()


def two_pane_chooser(host: str, current: set[str], choices: dict[str, str]):
    """The Textual chooser: bundles on the left, what they install on the right.

    Returns the new selection, None if cancelled, or UNAVAILABLE if Textual is
    not importable or refuses to start. `gisnix configure` declares Textual through
    the flake so it is always there, but running this file straight out of a
    checkout on a machine without it should degrade to the single-column gum
    picker rather than fail — the guarantees about what gets written live in
    hostconfig.py, not here.
    """
    try:
        sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
        import configure_tui
    except ImportError:
        return UNAVAILABLE
    try:
        return configure_tui.choose(host, current, choices)
    except Exception as exc:  # noqa: BLE001 - any failure means fall back
        warn(f"the two-pane chooser would not start ({exc})")
        warn("falling back to the single-column picker")
        return UNAVAILABLE


def choose_bundles(catalogue: list[dict], current: set[str]) -> set[str]:
    known = {b["name"] for b in catalogue}
    width = columns()
    labels = {b["name"]: label_for(b, width) for b in catalogue}

    if not has_gum():
        say()
        for b in catalogue:
            mark = "x" if b["name"] in current else " "
            say(f"  [{mark}] {labels[b['name']]}")
        say()
        say(f"  {DIM}Type the bundles you want, space separated. Enter keeps them as they are.{NC}")
        answer = input("  > ").strip()
        if not answer:
            return set(current)
        chosen = set(answer.split())
        unknown = chosen - known
        if unknown:
            die("not a bundle: " + ", ".join(sorted(unknown)))
        return chosen

    selected = [labels[n] for n in sorted(current & known)]
    args = [
        "choose",
        "--no-limit",
        "--header",
        "Which bundles? (space toggles, enter confirms, esc cancels)",
        "--height",
        str(max(8, min(len(catalogue) + 2, rows() - 5))),
    ]
    if selected:
        args += ["--selected", ",".join(selected)]
    out = gum(*args, "--", *(labels[b["name"]] for b in catalogue))

    chosen = set()
    for line in out.split("\n"):
        if not line.strip():
            continue
        name = name_from_label(line, known)
        if name is None:
            die(f"could not read a bundle name back from {line.strip()!r}")
        chosen.add(name)
    return chosen


def choose_locale(current: str | None) -> str | None:
    options = H.choices()
    if not options:
        return None
    keep = "leave as it is" if current else "do not set one"
    if not has_gum():
        say("  locales: " + ", ".join(options))
        answer = input(f"  locale? [{current or keep}] ").strip()
        return answer or current
    args = [
        "choose",
        "--header",
        f"Locale? (currently {current or 'unset'})",
        "--height",
        str(min(len(options) + 3, max(6, rows() - 6))),
    ]
    if current in options:
        args += ["--selected", current]
    picked = gum(*args, "--", keep, *options)
    return current if picked == keep else picked


def choose_kernel(current: str | None) -> str | None:
    """Pick the kernel, for the gum fallback only.

    The Textual chooser shows these as rows under `base`; this is what runs
    when Textual is unavailable. Deliberately blunt about what `latest`
    costs.

    The two options are not symmetric: one is prebuilt on Hydra and the other
    compiles a kernel and a ZFS module on the machine. Someone ticking a box
    in a menu should be told that before they tick it, not afterwards while
    they wait.
    """
    options = H.choice_values("kernel")
    group = H.choice_group("kernel") or {}
    notes = group.get("choiceNotes", {})
    blurb = {
        "stable": "the NixOS default — prebuilt, nothing to compile",
        "latest": "kernel 7.2 + OpenZFS 2.4.4 from master — COMPILES LOCALLY, hours",
    }
    blurb = {v: blurb.get(v, notes.get(v, "")) for v in options}
    current = current or H.choice_default("kernel")
    if not has_gum():
        for name in options:
            say(f"  {name:<8} {DIM}{blurb[name]}{NC}")
        answer = input(f"  kernel? [{current}] ").strip()
        return answer or current
    labels = [f"{name:<8} {blurb[name]}" for name in options]
    args = [
        "choose",
        "--header",
        f"Kernel? (currently {current})",
        "--height",
        str(min(len(options) + 3, max(6, rows() - 6))),
    ]
    if current in options:
        args += ["--selected", labels[options.index(current)]]
    picked = gum(*args, "--", *labels)
    for name, label in zip(options, labels):
        if picked == label:
            return name
    return current


# ── reporting ─────────────────────────────────────────────────────────────


def report_state(config: H.HostConfig, host: str) -> None:
    """The host's current position on every bundle, grouped as the file is."""
    catalogue = H.catalogue()
    heading(f"{host} — {_rel(config.path)}")
    if not config.has_block:
        warn("this host has no `bundles` block; it imports its software directly")

    group = None
    for bundle in catalogue:
        head = bundle["path"].split("/")[0]
        if head != group:
            group = head
            say(f"  {DIM}{H.B.title_for(head)}{NC}")
        on = bundle["name"] in config.enabled
        count = len(bundle.get("modules", []))
        modules = f"{count} module" + ("" if count == 1 else "s")
        row = f"{_name_cell(bundle):<{name_column()}}{modules}"
        say(f"    {GREEN}● {row}{NC}" if on else f"    {DIM}○ {row}{NC}")

    say()
    picked = ", ".join(
        f"{g['choiceKey']} "
        f"{config.choices.get(g['choiceKey']) or g.get('choiceDefault') or 'unset'}"
        for g in H.choice_groups()
    )
    say(f"  {len(config.enabled)} of {len(catalogue)} bundles{DIM}, {picked}{NC}")
    for name in config.unknown:
        warn(f"{name} is named here but is not a bundle under software/")
    say()


def report_change(
    before: set[str],
    after: set[str],
    locale_before,
    locale_after,
    brought: dict[str, str] | None = None,
    dropped_with: dict[str, str] | None = None,
    choices_before: dict[str, str] | None = None,
    choices_after: dict[str, str] | None = None,
) -> bool:
    """Print what is about to change. Returns True when something is."""
    brought = brought or {}
    dropped_with = dropped_with or {}
    added = sorted(after - before)
    removed = sorted(before - after)
    heading("What changes")
    for name in added:
        why = brought.get(name)
        tail = f" {DIM}← came with {why}{NC}" if why else ""
        say(f"  {GREEN}+ {name}{NC}{tail}")
    for name in removed:
        why = dropped_with.get(name)
        tail = f" {DIM}← went with {why}{NC}" if why else ""
        say(f"  {RED}- {name}{NC}{tail}")
    if locale_after != locale_before:
        say(f"  {BLUE}~ locale {locale_before or 'unset'} → {locale_after}{NC}")

    # Every other one-of group, reported the same way. Named generically so a
    # group added tomorrow shows up here without being remembered.
    before_choices = dict(choices_before or {})
    after_choices = dict(choices_after or {})
    switched = {
        key
        for key in set(before_choices) | set(after_choices)
        if key != H.CHOICE_KEY and before_choices.get(key) != after_choices.get(key)
    }
    for key in sorted(switched):
        was = before_choices.get(key) or "unset"
        now = after_choices.get(key) or "unset"
        say(f"  {BLUE}~ {key} {was} → {now}{NC}")
        note = (H.choice_group(key) or {}).get("choiceWarning", {}).get(now)
        if note:
            warn(note)

    if not added and not removed and locale_after == locale_before and not switched:
        say(f"  {DIM}nothing — the selection matches the file{NC}")
        return False
    return True


def report_opt_ins(after: set[str], brought: dict[str, str]) -> None:
    """Name the children a cascade deliberately left alone, and why.

    Silence here would read as "that group has no more to it". These are the
    two bundles whose own `bundle.json` says not to take them as a side
    effect, so the tool has to say it declined rather than simply not doing
    it.
    """
    skipped = []
    for name in sorted(after):
        for child in H.children_of(name):
            reason = H.opt_in(child)
            if reason and child not in after:
                skipped.append((child, name, reason))
    if not skipped:
        return
    say()
    say(f"  {DIM}left alone — these are opt-in, and are never added for you:{NC}")
    for child, parent, reason in skipped:
        say(f"    {YELLOW}○{NC} {child} {DIM}(inside {parent}){NC}")
        for line in textwrap.wrap(reason, width=min(66, max(40, columns() - 12))):
            say(f"      {DIM}{line}{NC}")
    say(f"    {DIM}add one by name: gisnix configure <host> --enable <bundle>{NC}")


def report_implications(after: set[str]) -> None:
    """Say what a selection drags in, and what it need not have named.

    Both are things a reader of the file cannot see for themselves: `implies`
    lives in `bundle.json`, not in `config.nix`.
    """
    resolved = set(H.resolve(sorted(after)))
    extra = sorted(resolved - after)
    if extra:
        say()
        say(f"  {DIM}also brought in, because something you picked needs it:{NC}")
        for name in extra:
            say(f"    {BLUE}↳{NC} {name}")

    redundant = H.implied_by(after)
    if redundant:
        say()
        say(f"  {DIM}named explicitly but already implied — harmless, and removable:{NC}")
        for name, causes in sorted(redundant.items()):
            say(f"    {DIM}·{NC} {name} {DIM}← {', '.join(causes)}{NC}")


def show_diff(path: Path, new_text: str) -> None:
    """The edit, as a coloured unified diff, before anything is written."""
    rel = _rel(path)
    with tempfile.TemporaryDirectory() as tmp:
        candidate = Path(tmp) / path.name
        candidate.write_text(new_text)
        proc = subprocess.run(
            [
                "git",
                "diff",
                "--no-index",
                "--no-prefix",
                "--color=always",
                "--",
                str(path),
                str(candidate),
            ],
            capture_output=True,
            text=True,
        )
        # --no-index diffs absolute paths, one of them a temporary directory,
        # and --no-prefix drops their leading slash in the header lines.
        # Nobody needs to read either form; say which file and which side.
        body = proc.stdout
        for absolute, label in ((candidate, "proposed"), (path, "now")):
            for form in (str(absolute), str(absolute).lstrip("/")):
                body = body.replace(form, f"{rel} ({label})")
    if not body.strip():
        say(f"  {DIM}the file is already exactly this{NC}")
        return
    heading("The edit")
    say(body.rstrip("\n"))


# ── validating and writing ────────────────────────────────────────────────


def parses(text: str) -> tuple[bool, str]:
    """Does this actually evaluate as Nix?

    Printing Nix that looks plausible is not evidence that it is valid —
    `gisnix create-host` learned that on its first real run. `nix-instantiate
    --parse` is a syntax check only: it reads the file and builds no store
    paths, so it is cheap and cannot touch the system.
    """
    if shutil.which("nix-instantiate") is None:
        return True, "nix-instantiate is not on PATH; syntax was not checked"
    with tempfile.TemporaryDirectory() as tmp:
        candidate = Path(tmp) / "config.nix"
        candidate.write_text(text)
        proc = subprocess.run(
            ["nix-instantiate", "--parse", str(candidate)],
            capture_output=True,
            text=True,
        )
    return proc.returncode == 0, proc.stderr.strip()


def formatted(text: str) -> str:
    """Run nixfmt over the result, when it is available.

    The renderer already emits RFC-style output, so this is normally a no-op.
    It runs anyway because pre-commit will format the file on the way in, and
    a tool whose output needs reformatting has produced a diff nobody asked
    for.
    """
    if shutil.which("nixfmt") is None:
        return text
    with tempfile.TemporaryDirectory() as tmp:
        candidate = Path(tmp) / "config.nix"
        candidate.write_text(text)
        proc = subprocess.run(["nixfmt", str(candidate)], capture_output=True, text=True)
        if proc.returncode != 0:
            warn("nixfmt refused the generated file; leaving it unformatted")
            return text
        return candidate.read_text()


def evaluates(host: str) -> tuple[bool, str]:
    """Does this host's configuration still evaluate? (answer, error).

    `nix-instantiate --parse` checks SYNTAX. It cannot know that a bundle
    pulls in an unfree package nothing has allowed, that two modules define
    the same option, or that an assertion now fails — every one of which
    produces a file that parses perfectly and a machine that will not build.

    Evaluating `system.build.toplevel.drvPath` walks the whole module system
    and every package's metadata without building anything. It is the same
    work `nixos-rebuild` does before it starts fetching, so a pass here means
    the rebuild gets at least as far.
    """
    if shutil.which("nix") is None:
        return True, "nix is not on PATH, so the configuration was not evaluated"
    proc = subprocess.run(
        [
            "nix",
            "eval",
            "--raw",
            f".#nixosConfigurations.{host}.config.system.build.toplevel.drvPath",
        ],
        capture_output=True,
        text=True,
        # The target's own flake, not gisnix's — nixosConfigurations.<host>
        # is defined in the consumer's flake.nix, wherever that lives.
        cwd=H.TARGET_ROOT,
    )
    return proc.returncode == 0, proc.stderr


def untracked_bundles() -> list[str]:
    """Bundle directories git does not know about.

    Nix reads the flake from the git tree, so a bundle created here and not
    staged is invisible to the evaluation that follows — it would pass, and
    the rebuild would then fail on an unknown bundle name.
    """
    proc = subprocess.run(
        ["git", "ls-files", "--others", "--exclude-standard", "software/"],
        capture_output=True,
        text=True,
        cwd=H.REPO_ROOT,
    )
    return [
        line for line in proc.stdout.split("\n") if line.endswith("bundle.json")
    ]


def nothing_to_do(host_changed: bool, module_edits: dict) -> bool:
    """Is there genuinely nothing to write?

    Its own function so the condition can be tested. The version inlined
    above it looked at the host file alone, which quietly discarded every
    package deletion made without also toggling a bundle.
    """
    return not host_changed and not module_edits


def _put_back(restore: dict) -> None:
    for target, text in restore.items():
        target.write_text(text)


def _evaluate_and_keep(host: str, restore: dict) -> bool:
    """Evaluate the host; undo everything written if it no longer works.

    This exists because the tool broke a machine. `services-device-peripherals`
    pulled in an unfree package nothing had allowed, every file parsed, and
    the failure surfaced at `nixos-rebuild` — by which point the config was
    already committed to disk and the operator had to work out which of
    several edits was responsible.
    """
    stray = untracked_bundles()
    if stray:
        warn("these bundles are not staged, so nix cannot see them:")
        for entry in stray:
            say(f"    {YELLOW}?{NC} {entry}")
        say(f"  {DIM}git add them, or the evaluation below is not the whole story.{NC}")

    say()
    say(f"  {DIM}Evaluating {host} — a minute or so, and it builds nothing.{NC}")
    good, error = evaluates(host)
    if good:
        if error:
            warn(error)
        else:
            ok(f"{host} evaluates")
        return True

    heading(f"{host} no longer evaluates — putting everything back")
    tail = [line for line in error.rstrip().split("\n") if line.strip()][-25:]
    for line in tail:
        say(f"  {DIM}{line}{NC}")
    _put_back(restore)
    say()
    for target in sorted(restore):
        ok(f"restored {_rel(target)}")
    say()
    say(f"  {DIM}Nothing was kept. The error above is what `nixos-rebuild` would{NC}")
    say(f"  {DIM}have shown you, except that it comes before the machine changed.{NC}")
    say(f"  {DIM}--no-eval skips this check if you know what you are doing.{NC}")
    say()
    return False


def report_module_edits(edits: dict) -> bool:
    """Show what changes under software/, and who it reaches. Confirms it too.

    Separated from the host diff on purpose. Editing config.nix changes one
    machine; editing a module changes every host taking the bundle, and the
    two should never be waved through by the same nod.
    """
    heading("Changes to software/ — these affect every host taking the bundle")
    for module, expected in sorted(edits.items()):
        current = set(M.I.packages_in(module)[0])
        rel = _rel(module)
        bundle = next(
            (b for b in H.catalogue() if str(rel).startswith(f"software/{b['path']}/")),
            None,
        )
        reach = M.hosts_using(bundle["name"]) if bundle else []
        say(f"  {BOLD}{rel}{NC}")
        for package in sorted(current - expected):
            say(f"    {RED}- {package}{NC}")
        for package in sorted(expected - current):
            say(f"    {GREEN}+ {package}{NC}")
        say(f"    {DIM}reaches {len(reach)} host(s): {', '.join(reach) or 'none'}{NC}")
    return True


# ── the command ───────────────────────────────────────────────────────────


def parse_names(value: str | None) -> set[str]:
    if not value:
        return set()
    return {n for n in re.split(r"[,\s]+", value.strip()) if n}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="gisnix configure",
        description="Turn a host's software bundles on and off.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
examples:
  gisnix configure                          this machine, then tick the bundles
  gisnix configure myhost                   straight to myhost's bundles
  gisnix configure myhost --list            show what it takes, change nothing
  gisnix configure myhost --enable desktop-gis
  gisnix configure myhost --disable terminal-ai,desktop-games
  gisnix configure myhost --set base,desktop-browsers --locale za-en
  gisnix configure myhost --kernel 7.2      run kernel 7.2 on this host
  gisnix configure myhost --enable security --dry-run

The bundle list always comes from software/**/bundle.json, so it is complete
whatever the host's config.nix currently mentions. See `gisnix bundles` for what
each one holds.
""",
    )
    parser.add_argument(
        "host",
        nargs="?",
        help="which host. Defaults to this machine, as `gisnix update` does; "
        "asked for only when this machine is not one of them",
    )
    parser.add_argument("-l", "--list", action="store_true", help="show state and exit")
    parser.add_argument("-e", "--enable", help="bundles to add, comma separated")
    parser.add_argument("-d", "--disable", help="bundles to remove, comma separated")
    parser.add_argument("-s", "--set", dest="exact", help="the exact set to end up with")
    parser.add_argument("--locale", help="set the host's locale, e.g. za-en")
    parser.add_argument(
        "--kernel",
        choices=H.choice_values("kernel"),
        help="which kernel the host boots. `stable` is the NixOS default and "
        "is prebuilt; `latest` takes kernel 7.2 and OpenZFS 2.4.4 from "
        "nixpkgs-master, which is not on Hydra, so the host compiles both "
        "itself. Normally picked in the chooser, where it is a row under "
        "`base`; this flag is for scripting",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="allow removing a bundle marked required, such as the one "
        "carrying this machine's bootloader",
    )
    parser.add_argument(
        "--no-eval",
        action="store_true",
        help="skip the `nix eval` of the host that normally follows a write. "
        "That check is what stops a change which parses but does not "
        "evaluate from reaching a rebuild",
    )
    parser.add_argument(
        "--no-cascade",
        action="store_true",
        help="do not add a bundle's children when you switch the bundle on",
    )
    parser.add_argument(
        "-n", "--dry-run", action="store_true", help="show the edit, write nothing"
    )
    parser.add_argument(
        "-y",
        "--yes",
        action="store_true",
        help="do not ask for confirmation. For scripts, and for output being "
        "redirected to a file — a gum prompt written to a file blocks forever "
        "and looks exactly like a hang.",
    )
    return parser


def main(argv: list[str]) -> int:
    args = build_parser().parse_args(argv)

    if not (H.REPO_ROOT / "software").is_dir():
        die("run this from the repo root")

    non_interactive = bool(
        args.enable or args.disable or args.exact or args.locale or args.kernel
    )

    host = args.host
    if host is None:
        # Same rule as `gisnix update`: no host means this machine. Picking your
        # own laptop out of a list of nine, every time, is a question with a
        # known answer.
        host = this_machine()
        if host is not None:
            say(f"  {DIM}no host given — defaulting to this machine: {NC}{BOLD}{host}{NC}")
        elif non_interactive or not interactive():
            die(
                f"this machine ({os.uname().nodename.split('.')[0]}) is not a host "
                f"in hosts/.\n    Name one: {', '.join(H.hosts())}"
            )
        else:
            # Not a fleet machine, but there is a terminal — ask rather than
            # refuse, which is the one place this differs from `gisnix update`.
            host = choose_host(None)
    if host not in H.hosts():
        die(f"no hosts/{host}/config.nix — known hosts: {', '.join(H.hosts())}")

    path = H.path_for(host)
    config = H.parse(path)

    if args.list:
        report_state(config, host)
        return 0

    catalogue = H.catalogue()
    known = {b["name"] for b in catalogue}
    before = set(config.enabled)

    if args.exact is not None:
        after = parse_names(args.exact)
    else:
        after = set(before)
    after |= parse_names(args.enable)
    after -= parse_names(args.disable)

    unknown = after - known
    if unknown:
        die(
            "not a bundle: "
            + ", ".join(sorted(unknown))
            + f"\n    known bundles: {', '.join(sorted(known))}"
        )

    explicitly_off = parse_names(args.disable)
    chosen_interactively = False
    #: module path -> the packages it should install, staged in the chooser's
    #: edit mode. These change software/, so they reach every host taking the
    #: bundle — which is why they get their own diff and their own confirm.
    module_edits: dict = {}

    locale = args.locale
    if locale is not None and H.choices() and locale not in H.choices():
        die(f"not a locale: {locale}\n    known: {', '.join(H.choices())}")

    # Flag-set choices, keyed as the registry keys them. argparse has already
    # rejected anything the registry does not offer.
    requested: dict[str, str] = {}
    if args.kernel is not None:
        requested["kernel"] = args.kernel
    if locale is not None:
        requested[H.CHOICE_KEY] = locale

    if not non_interactive:
        if not interactive():
            die("no terminal to draw on; use --enable/--disable/--set instead")
        # No state listing here. The picker below shows the same tree with
        # the same bundles already ticked, so printing it first was the same
        # information twice — and pushed the picker off the top of a short
        # terminal. `--list` still prints it, which is what --list is for.
        if not config.has_block and not confirm(
            f"{host} has no bundles block. Add one?", assume_yes=args.yes
        ):
            say("  left alone.")
            return 0
        current_choices = {
            g["choiceKey"]: value
            for g in H.choice_groups()
            for value in [config.choices.get(g["choiceKey"]) or g.get("choiceDefault")]
            if value is not None
        }
        picked = two_pane_chooser(host, before, current_choices)
        if picked is UNAVAILABLE:
            after = choose_bundles(catalogue, before)
        elif picked is None:
            say("  cancelled — nothing was written.")
            return 0
        else:
            after = picked.selected
            module_edits = picked.edits
            # The chooser applies the family rules on every keystroke, so its
            # answer is final. Cascading over it again would undo the operator
            # untickng one child of a group they were otherwise taking: the
            # parent counts as newly-on, and the cascade would put the child
            # straight back.
            chosen_interactively = True
            # The one-of groups are rows in that same tree now, so there is
            # nothing left to ask afterwards. They were separate prompts, and
            # a menu whose whole job is to show everything a machine can take
            # did not show the kernel or the locale at all.
            requested.update(picked.choices)
            locale = requested.get(H.CHOICE_KEY, locale)

        if picked is UNAVAILABLE:
            # The gum fallback has one column and no tree, so the groups go
            # back to being their own prompts there.
            locale = choose_locale(config.locale)
            if locale is not None:
                requested[H.CHOICE_KEY] = locale
            fallback_kernel = choose_kernel(config.kernel)
            if fallback_kernel is not None:
                requested["kernel"] = fallback_kernel

    # Taking a group takes what is in it. Only what this edit switched ON
    # cascades, and anything switched off in the same breath stays off, so
    # unticking one child of a group you are keeping does what it looks like.
    brought, dropped_with = {}, {}
    if not args.no_cascade and not chosen_interactively:
        expanded, brought = H.cascade(after - before)
        after = (after | expanded) - (before - after) - explicitly_off

    # Switching a parent off switches its children off, always — not just
    # when --cascade is on. A child names its parent in `implies`, so a host
    # keeping the child gets the parent regardless of what its config.nix
    # says; leaving one behind turns the removal into a line that lies.
    swept, dropped_with = H.cascade_off(before - after)
    after -= swept
    after |= parse_names(args.enable) - explicitly_off

    locale_after = requested.get(H.CHOICE_KEY, config.locale)

    # The effective value of every one-of group after this edit: what was
    # asked for, else what the file already said, else the group's default.
    choices_before = {
        g["choiceKey"]: config.choices.get(g["choiceKey"]) or g.get("choiceDefault")
        for g in H.choice_groups()
    }
    choices_before = {k: v for k, v in choices_before.items() if v is not None}
    choices_after = dict(choices_before)
    for key, value in requested.items():
        choices_after[key] = value

    refused = H.removals_refused(before, after)
    if refused and not args.force:
        heading(f"Refusing to take a bundle off {host}")
        say(f"  {DIM}This is about which bundles the host takes, not about any{NC}")
        say(f"  {DIM}package edits — those are described below, and are not written{NC}")
        say(f"  {DIM}either. Nothing at all has changed on disk.{NC}")
        say()
        for name, why in refused.items():
            say(f"  {RED}✗ {name}{NC} {DIM}would be dropped from this host{NC}")
            for line in textwrap.wrap(why, width=min(70, max(40, columns() - 8))):
                say(f"    {DIM}{line}{NC}")
        say()
        # Say what else the run would have done, so a selection changed by
        # accident is recognisable as an accident rather than as the point.
        report_change(
            before,
            after,
            config.locale,
            locale_after,
            brought,
            dropped_with,
            choices_before,
            choices_after,
        )
        if module_edits:
            report_module_edits(module_edits)
        say()
        say(f"  {DIM}If you did not mean to drop it, run again and leave it ticked.{NC}")
        say(f"  {DIM}--force overrides, if you genuinely mean it and have a way{NC}")
        say(f"  {DIM}back into the machine that does not need it.{NC}")
        say()
        return 1

    changed = report_change(
        before,
        after,
        config.locale,
        locale_after,
        brought,
        dropped_with,
        choices_before,
        choices_after,
    )

    # Anything still dragged back in by `implies` after all of that.
    coming_back = H.resurrected(after, before - after)
    if coming_back:
        say()
        warn("these are removed here but arrive anyway, because something you kept needs them:")
        for name, causes in sorted(coming_back.items()):
            say(f"    {YELLOW}↺{NC} {name} {DIM}← {', '.join(causes)}{NC}")
        say(f"  {DIM}Drop those too if you meant it, or leave the line as it was.{NC}")

    if after:
        report_implications(after)
    report_opt_ins(after, brought)
    if config.unknown:
        say()
        for name in config.unknown:
            warn(f"{name} is not a bundle and will be commented out, not deleted")

    carried = sum(len(e.notes) for e in config.entries)
    if carried:
        say()
        for line in textwrap.wrap(
            f"{carried} note{'' if carried == 1 else 's'} written about this machine "
            f"{'is' if carried == 1 else 'are'} kept, each above the bundle it "
            f"annotated. Anything there that merely repeats the bundle's own "
            f"description is safe to delete by hand.",
            width=min(74, max(40, columns() - 6)),
        ):
            say(f"  {DIM}{line}{NC}")

    # Write a key only when it says something. A host that has never carried
    # one and is choosing the group's default stays as it is, so a run that
    # changes no bundles does not rewrite every config.nix in the fleet to add
    # `kernel = "stable"` — which would also make report_change's "nothing
    # changed" a lie.
    choices_write = {
        key: value
        for key, value in choices_after.items()
        if key != H.CHOICE_KEY
        and (config.choices.get(key) is not None or value != H.choice_default(key))
    }

    new_text = formatted(
        H.render(config, after, locale=locale_after, choices=choices_write)
    )
    host_changed = new_text != config.text

    # Both halves have to be considered here. Testing only the host file meant
    # that deleting a package without also changing a bundle hit "nothing to
    # write" and threw the edit away — having reported nothing, so the module
    # looked edited until you opened it again.
    if nothing_to_do(host_changed, module_edits):
        say()
        ok("nothing to write — the files already say this.")
        return 0

    if host_changed:
        problems = H.verify(new_text, after, locale_after, choices=choices_write)
        if problems:
            die(
                "the rendered file does not say what was asked:\n    "
                + "\n    ".join(problems)
            )

        valid, message = parses(new_text)
        if not valid:
            die("the rendered file does not parse as Nix — refusing to write it:\n" + message)
        if message:
            warn(message)

        show_diff(path, new_text)

    if module_edits and not report_module_edits(module_edits):
        return 1

    if args.dry_run:
        say()
        ok("--dry-run: nothing was written.")
        return 0

    say()
    if not changed:
        say(f"  {DIM}The bundle selection is unchanged; this only reshapes the file.{NC}")
    if not confirm(f"Write this to {_rel(path)}?", assume_yes=args.yes):
        say("  left alone.")
        return 0

    # Every file's previous contents, so a configuration that no longer
    # evaluates can be put back exactly as it was.
    restore: dict[Path, str] = {}

    for module, expected in sorted(module_edits.items()):
        restore[module] = module.read_text()
        try:
            M.apply(module, M.rendered(module, expected), expected)
        except M.Refused as refused:
            _put_back(restore)
            die(f"{_rel(module)}: {refused}")
        ok(f"wrote {_rel(module)}")

    if host_changed:
        restore[path] = config.text
        H.write(path, new_text)
        say()
        ok(f"wrote {_rel(path)}")

    if not args.no_eval and not _evaluate_and_keep(host, restore):
        return 1
    say(f"  {DIM}the previous version is in git — `git diff` to review, "
        f"`git checkout` to undo{NC}")
    say()
    say(f"  {BLUE}💁{NC}  apply it: {BOLD}gisnix update {host}{NC}")
    say(f"  {DIM}    one bundle at a time is the safe way to add several: a build "
        f"that fails then names its own cause.{NC}")
    say()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
