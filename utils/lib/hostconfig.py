"""Read and rewrite the `bundles` block in `hosts/<name>/config.nix`.

This is the editing half of the bundle system. `software/bundles.nix` and
`docs/scripts/bundles.py` answer *what bundles exist*; this answers *which
ones a host has switched on*, and rewrites that answer back into the file
without disturbing anything else in it.

`utils/configure.sh` (`gisnix configure`) is the interactive front end, and
`utils/gen-host-config.py` uses the same renderer so a host created by
`gisnix create-host` and a host edited by `gisnix configure` produce byte-identical
shapes. One renderer, so the two cannot drift.

WHY THE FILE IS REWRITTEN RATHER THAN PATCHED

A line-level patch — comment this line out, uncomment that one — only works
on a file that already lists every bundle. Most hosts list a handful, so
"enable desktop-gis" would have nowhere to put the line, and the tool would
have to invent placement rules. Rewriting the whole block from the registry
means the file always states its position on *every* bundle: taken, or
deliberately not taken. Nothing is missing because nobody thought of it.

Rewriting is only safe if it loses nothing, so:

  * everything outside `bundles = [ … ];` is copied through byte for byte —
    the host's prose header, its other keys, its trailing notes
  * comments *inside* the block that say something the registry does not are
    carried over and reattached to the bundle they annotated
  * comments that merely restate a bundle's own description, and decorative
    rules, are dropped — they are regenerated from `bundle.json`
  * a name in the file that matches no bundle is never silently discarded;
    it is reported to the caller and parked as a commented entry

ORDER AND DUPLICATES

Entries are emitted in the registry's presentation order (base, terminal,
desktop, services, security) regardless of the order they were found in, and
a set is used throughout, so a name cannot appear twice. Toggling one bundle
therefore produces a one-line diff, whatever state the file arrived in.
"""

from __future__ import annotations

import os
import re
import sys
import textwrap
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT / "docs" / "scripts"))

import bundles as B  # noqa: E402

#: Width the rendered block wraps its comments to, including indentation.
WIDTH = 76

#: The key this module manages as a list.
LIST_KEY = "bundles"

#: The locale key, kept as a name because enough callers say `config.locale`
#: by hand. It is otherwise an ordinary choice group like any other.
CHOICE_KEY = "locale"
CHOICE_BUNDLE = "locale"

_STRING = re.compile(r'"([^"\\]*(?:\\.[^"\\]*)*)"')
_BUNDLES_OPEN = re.compile(r"^(\s*)" + LIST_KEY + r"\s*=\s*\[")


def _scalar_re(key: str) -> re.Pattern:
    """Match `  key = "value";`, capturing the indent and the value."""
    return re.compile(r'^(\s*)' + re.escape(key) + r'\s*=\s*"([^"]*)"\s*;')


_CHOICE_LINE = _scalar_re(CHOICE_KEY)


# ── the registry ──────────────────────────────────────────────────────────


def catalogue() -> list[dict]:
    """Every bundle a host may name in `bundles`, in presentation order.

    Bundles marked `selection = "one-of"` are excluded: their members are
    alternatives, not a set, so a host names the member rather than the
    group. `locale` is the case that exists today, and it is handled by
    `CHOICE_KEY` below rather than by the list.

    The order NESTS: a bundle is immediately followed by the bundles whose
    directory sits inside its own. `docs/scripts/bundles.py` sorts by depth
    first, which puts every parent above every child and leaves
    `services-device-input` eleven rows below the `services-device` it
    belongs to — fine for a reference page read top to bottom, useless for a
    menu, where the relationship is the thing you are choosing by.

    Each entry gains `depth`: 0 for a top-level bundle, 1 for a child.
    """
    flat = [b for b in B.load() if b.get("selection") != "one-of"]
    paths = {b["path"] for b in flat}

    kids: dict[str | None, list[dict]] = {}
    for bundle in flat:
        kids.setdefault(parent_path(bundle["path"], paths), []).append(bundle)

    ordered: list[dict] = []

    def walk(path: str | None, depth: int) -> None:
        for bundle in kids.get(path, []):
            ordered.append(bundle | {"depth": depth})
            walk(bundle["path"], depth + 1)

    walk(None, 0)
    return ordered


def choice_groups() -> list[dict]:
    """The one-of bundles, each with the legal values for its scalar key.

    A choice group is a bundle whose members are alternatives rather than
    companions — `software/locale/` (a machine has one locale, not eight) and
    `software/base/kernel/` (one kernel, not two). The host names the member
    it wants with the group's `choiceKey` instead of listing it in `bundles`.

    Values come from the module filenames, exactly as `profiles/bundles.nix`
    resolves them: `kernel-latest.nix` under `modulePrefix = "kernel"` is the
    value `latest`. Deriving both from the same convention is what stops the
    menu from offering a value that resolves to no file.
    """
    groups = []
    for bundle in B.load():
        if bundle.get("selection") != "one-of":
            continue
        key = bundle.get("choiceKey")
        if not key:
            continue
        prefix = bundle.get("modulePrefix", key)
        values = [
            m[len(prefix) + 1 : -len(".nix")]
            for m in bundle.get("modules", [])
            if m.startswith(prefix + "-") and m.endswith(".nix")
        ]
        groups.append(bundle | {"values": values})
    return groups


def choice_group(key: str) -> dict | None:
    """The choice group driving one scalar key, if there is one."""
    for group in choice_groups():
        if group["choiceKey"] == key:
            return group
    return None


def choice_values(key: str) -> list[str]:
    group = choice_group(key)
    return group["values"] if group else []


def choice_default(key: str) -> str | None:
    """What the host gets when it names no value.

    None means "no member is imported", which is a real answer: for `locale`
    it means no locale module, and for `kernel` it means the NixOS default,
    which is what the `stable` member documents.
    """
    group = choice_group(key)
    return group.get("choiceDefault") if group else None


def scalar_note(key: str) -> str | None:
    """The comment written above a scalar key added to a file lacking one.

    Taken from the group's own `bundle.json` description, so the file and the
    menu explain the choice in the same words rather than two that drift.
    """
    group = choice_group(key)
    return group.get("description") if group else None


def parent_path(path: str, paths: set[str]) -> str | None:
    """The nearest bundle directory this one sits inside, if any.

    `services/device/input` -> `services/device`. Note that `desktop` and
    `services` are containers rather than bundles, so a top-level bundle such
    as `desktop/browsers` has no parent — being in the same directory as
    another bundle is not a relationship.
    """
    above = [p for p in paths if path.startswith(p + "/")]
    return max(above, key=len) if above else None


def children_of(name: str) -> list[str]:
    """The bundles nested inside this one, deepest included, in menu order."""
    index = {b["name"]: b for b in catalogue()}
    parent = index.get(name)
    if parent is None:
        return []
    prefix = parent["path"] + "/"
    return [b["name"] for b in catalogue() if b["path"].startswith(prefix)]


def choices() -> list[str]:
    """The legal values for the `locale` key, e.g. `["pt-en", "za-en", …]`.

    A thin alias for `choice_values(CHOICE_KEY)`, kept because enough callers
    say `H.choices()` and mean the locale group specifically. The derivation
    lives in `choice_groups` now, so locale and kernel read their values the
    same way.
    """
    return choice_values(CHOICE_KEY)


def implied_by(selected: set[str]) -> dict[str, list[str]]:
    """Which selected bundles are already pulled in by another selected one.

    `desktop-gis` implies `desktop-environments-cosmic`, so naming both is
    harmless but redundant. Returning the reason — not just the fact — is
    what lets the caller say *why* a line can go.
    """
    index = B.by_name()
    reasons: dict[str, list[str]] = {}
    for name in sorted(selected):
        bundle = index.get(name)
        if bundle is None:
            continue
        for pulled in B.resolve([name])[1:]:
            if pulled in selected:
                reasons.setdefault(pulled, []).append(name)
    return reasons


def cascade(turned_on: set[str]) -> tuple[set[str], dict[str, str]]:
    """The children of bundles just switched on. Returns (set, why).

    Call this with what the edit ADDED, not with the whole selection.
    Turning something on brings its children; turning something off must
    never turn anything on. Cascading over the full selection instead would
    mean `--disable services-device-input` silently did nothing, because the
    still-selected `services-device` above it would put the child straight
    back — the tool reporting a change it had just undone.


    Choosing `services-device` means choosing Bluetooth and firmware updates;
    it should also mean the keyboards, the phones and the printer, because
    that is what the directory says the group is. Having to tick five boxes
    to say one thing is how a host ends up missing a sub-bundle nobody
    noticed was separate.

    EXCEPT where the bundle says not to. A bundle marked `"optIn": true` in
    its `bundle.json` is never selected on a host's behalf — it must be asked
    for by name. Two carry that mark today and both earn it:
    `services-device-peripherals`, because biometrics can decide whether you
    can log in at all, and `desktop-gis-source-builds`, because it is hours
    of compilation for an application the binary channels already provide.
    Cascading either onto a host as a side effect of ticking its parent is
    precisely the surprise those descriptions warn about.

    `why` maps each added name to the parent that brought it, so the caller
    can say where an unasked-for line came from rather than just showing it.
    """
    index = {b["name"]: b for b in catalogue()}
    out = set(turned_on)
    why: dict[str, str] = {}
    for name in sorted(turned_on):
        for child in children_of(name):
            if child in out:
                continue
            if index.get(child, {}).get("optIn"):
                continue
            out.add(child)
            why[child] = name
    return out, why


def required(name: str) -> str | None:
    """Why this bundle must not be taken away, if it must not.

    "Required" means a host that HAS it cannot be made to drop it by ticking
    a box. It deliberately does not mean every host must have it: a host that
    imports its software directly and takes neither of the two that carry
    the mark is not forced onto them — that would change what that machine
    installs, a tool protecting you from a mistake by making a different one.
    """
    bundle = {b["name"]: b for b in catalogue()}.get(name, {})
    if not bundle.get("required"):
        return None
    return bundle.get("requiredReason") or "marked required"


def removals_refused(before: set[str], after: set[str]) -> dict[str, str]:
    """Required bundles this edit would take off a host that has them."""
    return {
        name: required(name)
        for name in sorted(before - after)
        if required(name) is not None
    }


def cascade_off(turned_off: set[str]) -> tuple[set[str], dict[str, str]]:
    """The children of bundles just switched off. Returns (set, why).

    The mirror of `cascade`, and not optional. Every child bundle IMPLIES its
    parent — `services-device-input` names `services-device` in its
    `implies` — so a host keeping the child gets the parent whatever its
    config.nix says. Dropping a parent while leaving a child behind therefore
    does nothing at all, except make the file claim something untrue: the
    line reads `# "services-device"` and the machine installs it anyway.

    Opt-in children go too. `optIn` means "never added on your behalf", not
    "never removed" — dropping a group you no longer want should not strand
    its parts.
    """
    out = set(turned_off)
    why: dict[str, str] = {}
    for name in sorted(turned_off):
        for child in children_of(name):
            if child not in out:
                out.add(child)
                why[child] = name
    return out, why


def resurrected(selected: set[str], removed: set[str]) -> dict[str, list[str]]:
    """Bundles this edit drops that something still selected drags back in.

    Reporting a removal that `implies` immediately undoes is worse than
    refusing it: the operator reads the diff, sees the line commented out,
    and believes the machine no longer has it.
    """
    back: dict[str, list[str]] = {}
    for name in sorted(selected):
        for pulled in B.resolve([name])[1:] if name in B.by_name() else []:
            if pulled in removed:
                back.setdefault(pulled, []).append(name)
    return back


def opt_in(name: str) -> str | None:
    """Why this bundle refuses to be selected on a host's behalf, if it does."""
    bundle = {b["name"]: b for b in catalogue()}.get(name, {})
    if not bundle.get("optIn"):
        return None
    return bundle.get("optInReason") or "marked opt-in"


def resolve(names: list[str]) -> list[str]:
    """`names` plus everything they imply, transitively.

    Unknown names are skipped rather than thrown on. The caller has already
    rejected them with a message naming the whole registry; throwing here
    would replace that with a stack trace.
    """
    index = B.by_name()
    return B.resolve([n for n in names if n in index])


def hosts() -> list[str]:
    """Every host in `hosts/` that has a `config.nix`, alphabetically."""
    root = REPO_ROOT / "hosts"
    return sorted(d.name for d in root.iterdir() if (d / "config.nix").is_file())


def path_for(host: str) -> Path:
    return REPO_ROOT / "hosts" / host / "config.nix"


# ── reading ───────────────────────────────────────────────────────────────


def split_comment(line: str) -> tuple[str, str | None]:
    """Split a line into its code and its `#` comment.

    A `#` inside a string is not a comment. That matters less in a list of
    bundle names than it would elsewhere, but the whole point of this module
    is that it does not corrupt files it did not expect.
    """
    i = 0
    in_string = False
    while i < len(line):
        c = line[i]
        if in_string:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_string = False
        elif c == '"':
            in_string = True
        elif c == "#":
            return line[:i], line[i + 1 :]
        i += 1
    return line, None


@dataclass
class Entry:
    """One bundle named in the block, on or off, with what was said about it."""

    name: str
    enabled: bool
    notes: list[str] = field(default_factory=list)
    inline: str | None = None
    known: bool = True


@dataclass
class HostConfig:
    """A parsed `hosts/<name>/config.nix`."""

    path: Path
    text: str
    lines: list[str]
    #: index of the `bundles = [` line, or None when the file has no block
    start: int | None
    #: index of the line carrying the block's closing `];`
    end: int | None
    indent: str
    entries: list[Entry]
    #: choice key -> value, for every one-of group the file names. Generic so
    #: a new choice group needs no field here; `locale` and `kernel` are
    #: views onto it, kept because plenty of callers say them by name.
    choices: dict[str, str] = field(default_factory=dict)
    #: choice key -> the line it sits on, for the same set of keys.
    choice_lines: dict[str, int] = field(default_factory=dict)

    @property
    def locale(self) -> str | None:
        return self.choices.get(CHOICE_KEY)

    @property
    def locale_line(self) -> int | None:
        return self.choice_lines.get(CHOICE_KEY)

    @property
    def kernel(self) -> str | None:
        return self.choices.get("kernel")

    @property
    def has_block(self) -> bool:
        return self.start is not None

    @property
    def enabled(self) -> set[str]:
        return {e.name for e in self.entries if e.enabled and e.known}

    @property
    def unknown(self) -> list[str]:
        """Names in the file that match no bundle in `software/`.

        These are evaluation errors waiting to happen — `software/bundles.nix`
        throws on an unknown name — so they are surfaced rather than dropped.
        """
        return [e.name for e in self.entries if not e.known and e.enabled]


def _find_block(lines: list[str]) -> tuple[int, int, str] | None:
    """Locate `bundles = [ … ];`, returning (start, end, indent).

    The end is found by counting brackets rather than by matching a closing
    line, so a single-line `bundles = [ "a" "b" ];` and a block spanning a
    hundred lines are the same case.
    """
    for i, line in enumerate(lines):
        code, _ = split_comment(line)
        m = _BUNDLES_OPEN.match(code)
        if not m:
            continue
        depth = 0
        for j in range(i, len(lines)):
            code_j, _ = split_comment(lines[j])
            scan = code_j[m.end() - 1 :] if j == i else code_j
            for ch in _STRING.sub('""', scan):
                if ch == "[":
                    depth += 1
                elif ch == "]":
                    depth -= 1
                    if depth == 0:
                        return i, j, m.group(1)
        # Unbalanced. Refuse rather than guess where the list ends.
        return None
    return None


def _interior(lines: list[str], start: int, end: int, indent: str) -> list[str]:
    """The block's contents, with the `bundles = [` and `];` scaffolding cut."""
    if start == end:
        code, comment = split_comment(lines[start])
        open_at = code.index("[")
        close_at = code.rindex("]")
        body = code[open_at + 1 : close_at]
        return [body + ("#" + comment if comment else "")]

    out: list[str] = []
    first_code, first_comment = split_comment(lines[start])
    head = first_code[first_code.index("[") + 1 :]
    if head.strip() or first_comment:
        out.append(head + ("#" + first_comment if first_comment else ""))
    out += lines[start + 1 : end]
    last_code, last_comment = split_comment(lines[end])
    tail = last_code[: last_code.rindex("]")]
    if tail.strip():
        out.append(tail)
    _ = indent, last_comment
    return out


def _is_rule(text: str) -> bool:
    """A decorative separator — `── Active ──`, `-----`, and friends."""
    stripped = text.strip()
    if not stripped:
        return False
    if stripped.startswith("──") or stripped.startswith("--"):
        return True
    return set(stripped) <= set("─-=_*·")


def _normalise(text: str) -> str:
    return " ".join(text.split())


#: How alike a note and a bundle's own description have to be before the note
#: is treated as a restatement of it. A block this tool wrote reproduces the
#: description verbatim, so round-tripping only needs equality; the threshold
#: is for the hand-written files that came first, where the note was somebody
#: paraphrasing `bundle.json` a few words differently. Set deliberately high:
#: dropping a paraphrase costs nothing, dropping a real note about *this
#: machine* loses knowledge that exists nowhere else.
RESTATEMENT = 0.75


def generated_notes(bundle: dict) -> list[str]:
    """The comment paragraphs the renderer writes above a bundle by itself.

    Emitted by `render_block` and recognised by `_clean_notes`, from this one
    definition. Keeping the two in step by hand did not last a single commit:
    adding the opt-in sentence to the renderer without teaching the reader
    about it meant every pass read it back as a host note and wrote it out
    again below the fresh copy.
    """
    out = [bundle.get("description", "")]
    if bundle.get("required"):
        out.append(
            "Required: `gisnix configure` will not remove this from a host that "
            "has it — " + bundle.get("requiredReason", "it is load-bearing") + "."
        )
    if bundle.get("optIn"):
        out.append(
            "Opt-in: never added by `gisnix configure` when you take the group "
            "above — " + bundle.get("optInReason", "ask for it by name") + "."
        )
    return [p for p in out if p]


def _clean_notes(paragraphs: list[list[str]], generated: list[str]) -> list[str]:
    """Drop notes the renderer would produce anyway; keep the rest.

    A block this tool has already written carries each bundle's own
    description above it. Reading that back and keeping it would double it on
    every pass, so anything that restates the registry goes, and anything that
    does not is somebody's hard-won note about *this machine* and stays.
    """
    import difflib

    ours = [_normalise(g) for g in generated]
    kept: list[str] = []
    for para in paragraphs:
        joined = _normalise(" ".join(para))
        if not joined:
            continue
        if any(
            joined == mine
            or mine.startswith(joined)
            or difflib.SequenceMatcher(None, joined.lower(), mine.lower()).ratio()
            >= RESTATEMENT
            for mine in ours
        ):
            continue
        kept.append(joined)
    return kept


def parse(path: Path) -> HostConfig:
    """Read a host's `config.nix` into something editable."""
    text = path.read_text()
    lines = text.split("\n")
    known = {b["name"] for b in B.load()}

    # Every scalar the registry knows about, found in one pass. Named fields
    # for the two that exist keep the callers readable; `chosen` is what a
    # third group would arrive in without touching this loop.
    patterns = {g["choiceKey"]: _scalar_re(g["choiceKey"]) for g in choice_groups()}
    chosen: dict[str, tuple[str, int]] = {}
    for i, line in enumerate(lines):
        code, _ = split_comment(line)
        for key, pattern in patterns.items():
            m = pattern.match(code)
            if m and key not in chosen:
                chosen[key] = (m.group(2), i)

    found_choices = {k: v for k, (v, _) in chosen.items()}
    choice_lines = {k: i for k, (_, i) in chosen.items()}

    found = _find_block(lines)
    if found is None:
        return HostConfig(
            path=path,
            text=text,
            lines=lines,
            start=None,
            end=None,
            indent="  ",
            entries=[],
            choices=found_choices,
            choice_lines=choice_lines,
        )

    start, end, indent = found
    entries: list[Entry] = []
    pending: list[list[str]] = [[]]

    def take_pending() -> list[list[str]]:
        nonlocal pending
        out = [p for p in pending if p]
        pending = [[]]
        return out

    for raw in _interior(lines, start, end, indent):
        code, comment = split_comment(raw)
        names = _STRING.findall(code)
        if names:
            notes = take_pending()
            for idx, name in enumerate(names):
                entries.append(
                    Entry(
                        name=name,
                        enabled=True,
                        notes=notes if idx == 0 else [],
                        inline=(_normalise(comment or "") or None) if idx == len(names) - 1 else None,
                        known=name in known,
                    )
                )
            continue

        if comment is None:
            # A blank line ends a paragraph without ending the run of notes.
            if not code.strip() and pending[-1]:
                pending.append([])
            continue

        body = comment.strip()
        off = re.match(r'^"([^"]+)"\s*(?:#\s*(.*?))?\s*$', body)
        if off and off.group(1) in known:
            entries.append(
                Entry(
                    name=off.group(1),
                    enabled=False,
                    notes=take_pending(),
                    inline=off.group(2) or None,
                    known=True,
                )
            )
            continue

        # A decorative rule is furniture, not prose. It also ends the
        # paragraph: without that, this tool's own "── Desktop ──" heading
        # glued itself to the description under it, the pair then matched no
        # bundle's text, and the whole thing was preserved as a note — which
        # grew the file by one heading on every single run.
        if not body or _is_rule(body):
            if pending[-1]:
                pending.append([])
            continue

        pending[-1].append(body)

    # Attach the surviving notes to the bundle each one preceded.
    index = B.by_name()
    for entry in entries:
        entry.notes = _clean_notes(entry.notes, generated_notes(index.get(entry.name, {})))

    return HostConfig(
        path=path,
        text=text,
        lines=lines,
        start=start,
        end=end,
        indent=indent,
        entries=entries,
        choices=found_choices,
        choice_lines=choice_lines,
    )


# ── rendering ─────────────────────────────────────────────────────────────


def _wrap(text: str, prefix: str) -> list[str]:
    """Wrap prose to the file's width, keeping `code spans` on one line.

    Without the guard, "`gisnix bundles`" wraps between the two words and the
    backticks end up on different lines, which reads as a typo in a file whose
    whole job is to be read.
    """
    guarded = re.sub(
        r"`[^`]+`", lambda m: m.group(0).replace(" ", "\x00"), _normalise(text)
    )
    return [
        f"{prefix}{line}".replace("\x00", " ")
        for line in textwrap.wrap(guarded, width=max(20, WIDTH - len(prefix)))
    ]


def _rule(title: str, prefix: str) -> str:
    line = f"{prefix}── {title} "
    return line + "─" * max(2, WIDTH - len(line))


def render_block(
    selected: set[str],
    *,
    indent: str = "  ",
    notes: dict[str, list[str]] | None = None,
    inline: dict[str, str] | None = None,
    orphans: list[str] | None = None,
) -> list[str]:
    """The whole `bundles = [ … ];` block, every bundle stated either way.

    `selected` names the bundles that are on. Everything else in the registry
    is emitted as a commented line under its own description, so the file is
    also the menu — `sudo nixos-rebuild switch` after uncommenting one line is
    a complete workflow without this tool.

    `notes` and `inline` carry forward host-specific comments recovered by
    `parse`. `orphans` are names the file claimed that no bundle answers to;
    they are parked at the end, commented and labelled, rather than lost.
    """
    notes = notes or {}
    inline = inline or {}
    body = indent + "  "
    prefix = body + "# "

    out = [f"{indent}{LIST_KEY} = ["]
    section = None
    first = True
    paths = {b["path"] for b in catalogue()}

    for bundle in catalogue():
        # Nested bundles get their own sub-heading rather than an indent.
        # Indenting them would read better and last exactly one commit:
        # nixfmt normalises every element of a list to the same column, so
        # the generator and the formatter would undo each other forever.
        # `services/device/input` heads its run as "Services · Device", using
        # the same title derivation the reference page uses.
        parent = parent_path(bundle["path"], paths)
        here = B.title_for(parent) if parent else B.title_for(bundle["path"].split("/")[0])
        if here != section:
            section = here
            if not first:
                out.append("")
            out.append(_rule(here, prefix))
            first = False
        else:
            out.append("")

        # A bare `#` between paragraphs. Without it the reader joins them into
        # one run of comment lines, which then matches neither paragraph on
        # its own and is preserved as if a human had written it — the file
        # growing a duplicated description on every pass.
        for i, paragraph in enumerate(generated_notes(bundle)):
            if i:
                out.append(prefix.rstrip())
            out += _wrap(paragraph, prefix)

        for note in notes.get(bundle["name"], []):
            out.append(prefix.rstrip())
            out += _wrap(note, prefix)

        comment = inline.get(bundle["name"])
        suffix = f" # {comment}" if comment else ""
        on = bundle["name"] in selected
        out.append(f'{body}{"" if on else "# "}"{bundle["name"]}"{suffix}')

    if orphans:
        out.append("")
        out.append(_rule("Unrecognised", prefix))
        out += _wrap(
            "These names were in this file but match no bundle under "
            "software/. An unknown name is an evaluation error, not a "
            "no-op, so they are commented out here rather than dropped. "
            "Delete them, or restore the bundle they referred to.",
            prefix,
        )
        for name in orphans:
            out.append(f'{body}# "{name}"')

    out.append(f"{indent}];")
    return out


#: Introduces a block inserted into a file that had none. A file that already
#: has a block keeps whatever prose its author wrote above it.
def _header(indent: str) -> list[str]:
    return _wrap(
        "Software bundles — the package sets this machine installs. A bundle "
        "is a directory under software/; see docs/references/bundles.md, or "
        "`gisnix bundles`, for what each one holds. Implications resolve "
        "automatically, so asking for desktop-gis brings in the COSMIC "
        "desktop it needs to display QGIS.",
        f"{indent}# ",
    ) + [
        f"{indent}#",
        *_wrap(
            "Every bundle is listed. Uncomment a line to take it, comment it "
            "out to drop it, or run `gisnix configure` and tick the boxes.",
            f"{indent}# ",
        ),
    ]


def render(
    config: HostConfig,
    selected: set[str],
    *,
    locale: str | None = None,
    kernel: str | None = None,
    choices: dict[str, str] | None = None,
) -> str:
    """The complete new text of the file, block replaced, all else preserved."""
    known = {b["name"] for b in catalogue()}
    # Anything asked for that is not a bundle, plus anything the file already
    # claimed that is not a bundle. Neither is discarded quietly.
    orphans = sorted({n for n in selected if n not in known} | set(config.unknown))
    selected = {n for n in selected if n in known}

    notes = {e.name: e.notes for e in config.entries if e.notes}
    inline = {e.name: e.inline for e in config.entries if e.inline}

    block = render_block(
        selected,
        indent=config.indent,
        notes=notes,
        inline=inline,
        orphans=orphans,
    )

    lines = list(config.lines)
    if config.has_block:
        lines[config.start : config.end + 1] = block
    else:
        lines = _insert_block(lines, block, config)

    # `locale=` and `kernel=` are sugar for the same dict, so a caller may
    # name the two that predate it without knowing about the general form.
    wanted = dict(choices or {})
    if locale is not None:
        wanted[CHOICE_KEY] = locale
    if kernel is not None:
        wanted["kernel"] = kernel
    for key in sorted(wanted):
        lines = _set_scalar(lines, key, wanted[key])

    text = "\n".join(lines)
    return text if text.endswith("\n") else text + "\n"


def _insert_block(lines: list[str], block: list[str], config: HostConfig) -> list[str]:
    """Put a new block into a file that has none.

    Above the `locale` key when there is one, so the two software keys sit
    together; otherwise before the attribute set's closing brace.
    """
    indent = config.indent
    payload = _header(indent) + block

    if config.locale_line is not None:
        at = config.locale_line
        # Keep any comment immediately above `locale` attached to it.
        while at > 0 and lines[at - 1].strip().startswith("#"):
            at -= 1
        return lines[:at] + payload + [""] + lines[at:]

    for i in range(len(lines) - 1, -1, -1):
        if lines[i].strip() == "}":
            head = lines[:i]
            while head and not head[-1].strip():
                head.pop()
            return head + [""] + payload + lines[i:]

    return lines + [""] + payload


def _set_scalar(lines: list[str], key: str, value: str) -> list[str]:
    """Set `key = "value";`, rewriting it in place if the file already has it.

    Rewriting in place keeps any comment the user wrote on that line, and
    keeps the key where they put it. Only a file that has never carried the
    key gets a fresh one appended, carrying the choice group's own
    description so the value does not arrive unexplained.
    """
    pattern = _scalar_re(key)
    for i, line in enumerate(lines):
        code, comment = split_comment(line)
        m = pattern.match(code)
        if m:
            lines[i] = f'{m.group(1)}{key} = "{value}";' + (
                f" #{comment}" if comment else ""
            )
            return lines

    note = scalar_note(key)
    for i in range(len(lines) - 1, -1, -1):
        if lines[i].strip() == "}":
            added = [""]
            if note:
                added += _wrap(note, "  # ")
            added.append(f'  {key} = "{value}";')
            return lines[:i] + added + lines[i:]
    return lines


# ── writing ───────────────────────────────────────────────────────────────


def verify(
    text: str,
    selected: set[str],
    locale: str | None = None,
    kernel: str | None = None,
    choices: dict[str, str] | None = None,
) -> list[str]:
    """Read the rendered text back and check it says what was asked.

    Rendering Nix that looks plausible is not evidence that it is correct —
    `gisnix create-host` learned that the expensive way. Parsing our own output
    and comparing it to the request costs nothing and catches a renderer that
    has quietly stopped emitting something.
    """
    import tempfile

    problems: list[str] = []
    with tempfile.NamedTemporaryFile("w", suffix=".nix", delete=False) as fh:
        fh.write(text)
        tmp = Path(fh.name)
    try:
        back = parse(tmp)
        known = {b["name"] for b in catalogue()}
        want = {n for n in selected if n in known}
        if back.enabled != want:
            missing = sorted(want - back.enabled)
            extra = sorted(back.enabled - want)
            if missing:
                problems.append(f"not written: {', '.join(missing)}")
            if extra:
                problems.append(f"written but not asked for: {', '.join(extra)}")

        listed = [e.name for e in back.entries]
        dupes = sorted({n for n in listed if listed.count(n) > 1})
        if dupes:
            problems.append(f"listed more than once: {', '.join(dupes)}")

        absent = sorted(known - set(listed))
        if absent:
            problems.append(f"bundle missing from the block: {', '.join(absent)}")

        wanted = dict(choices or {})
        if locale is not None:
            wanted[CHOICE_KEY] = locale
        if kernel is not None:
            wanted["kernel"] = kernel
        for key, value in sorted(wanted.items()):
            if back.choices.get(key) != value:
                problems.append(
                    f"{key} is {back.choices.get(key)!r}, expected {value!r}"
                )
    finally:
        tmp.unlink(missing_ok=True)
    return problems


def write(path: Path, text: str) -> None:
    """Replace the file atomically, so an interrupted write cannot truncate it."""
    tmp = path.with_suffix(path.suffix + ".gisnix-new")
    tmp.write_text(text)
    os.replace(tmp, path)
