#!/usr/bin/env python3
"""Generate keyboard-layout SVG diagrams for the default kanata layer.

gisnix ships one kanata mechanism (software/services/device/input/
kanata-config.nix), applied to whichever physical board a host has. What
differs between hosts is only the `kanataLayout` knob (see kanata-
keyboard.nix) — "us" or "pt" — which picks the board geometry and the
chord output keycodes. So there is one diagram set per layout, not one per
host:

  docs/assets/keyboards/<layout>-keyboard-base-layer.svg
  docs/assets/keyboards/<layout>-keyboard-nav-layer.svg
  docs/assets/keyboards/<layout>-keyboard-herdr-layer.svg

Run from the repo root:
  python3 docs/scripts/generate-keyboard-diagrams.py

A downstream flake with its own per-host extras (a second kanata instance,
a different chord set, the opt-in aerc mail-client layer) draws its own
diagrams for those — this script only covers the mechanism gisnix itself
ships, which is why the herdr layer is here (the `base` bundle installs
herdr, so kanata-keyboard.nix turns its layer on by default) and aerc is
not (gisnix does not install aerc).
"""

import colorsys
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent.parent

GREEN = "#39FF14"  # Super
BLUE = "#569FC6"  # Alt / nav movement
RED = "#CC0403"  # Ctrl
AMBER = "#FFD400"  # Shift / nav left-click
CYAN = "#00E5FF"  # nav right-click
VIOLET = "#B14FFF"  # nav scroll
PINK = "#FF2D95"  # layer activators
GRAY = "#8A8B8B"  # bracket chords
TEAL = "#06969A"  # plain key
DARK = "#2A2B2B"  # unlit key (held-layer views)
BG = "#1B1C1C"
PANEL = "#242525"
TEXT = "#F5F5F2"

UNIT = 54  # key size in px
GAP = 6

# ---------------------------------------------------------------------------
# Board geometries. (label, width-in-units, colour-key) per row; the colour
# key names the LOGICAL key so the views below stay board-independent — e.g.
# the ";" home-row mod sits on Ç on the pt-PT board and on ; on US.

PT_ISO_ROWS = [
    [
        ("Esc", 1, "esc"), ("F1", 1, "f1"), ("F2", 1, "f2"), ("F3", 1, "f3"),
        ("F4", 1, "f4"), ("F5", 1, "f5"), ("F6", 1, "f6"), ("F7", 1, "f7"),
        ("F8", 1, "f8"), ("F9", 1, "f9"), ("F10", 1, "f10"), ("F11", 1, "f11"),
        ("F12", 1, "f12"), ("Del", 1, None),
    ],
    [
        ("\\", 1, None), ("1", 1, "1"), ("2", 1, "2"), ("3", 1, "3"),
        ("4", 1, "4"), ("5", 1, "5"), ("6", 1, "6"), ("7", 1, "7"),
        ("8", 1, "8"), ("9", 1, "9"), ("0", 1, "0"), ("'", 1, None),
        ("«", 1, None), ("Bksp", 1.5, None),
    ],
    [
        ("Tab", 1.5, "tab"), ("Q", 1, "q"), ("W", 1, "w"), ("E", 1, "e"),
        ("R", 1, "r"), ("T", 1, "t"), ("Y", 1, "y"), ("U", 1, "u"),
        ("I", 1, "i"), ("O", 1, "o"), ("P", 1, "p"), ("«", 1, None),
        ("+", 1, None), ("Enter", 1.5, None),
    ],
    [
        ("Caps", 1.75, "caps"), ("A", 1, "a"), ("S", 1, "s"), ("D", 1, "d"),
        ("F", 1, "f"), ("G", 1, "g"), ("H", 1, "h"), ("J", 1, "j"),
        ("K", 1, "k"), ("L", 1, "l"), ("Ç", 1, ";"), ("º", 1, None),
        ("~", 1, None), ("", 0.75, None),
    ],
    [
        ("Shift", 1.25, "lsft"), ("<", 1, "102d"), ("Z", 1, "z"),
        ("X", 1, "x"), ("C", 1, "c"), ("V", 1, "v"), ("B", 1, "b"),
        ("N", 1, "n"), ("M", 1, "m"), (",", 1, ","), (".", 1, None),
        ("-", 1, None), ("Shift", 2.25, "rsft"),
    ],
    [
        ("Ctrl", 1.25, "lctrl"), ("Super", 1.25, "super"), ("Alt", 1.25, "lalt"),
        ("Space", 6.25, "spc"), ("AltGr", 1.25, "altgr"), ("Fn", 1, None),
        ("Menu", 1.25, "menu"), ("Ctrl", 1.5, "rctrl"),
    ],
]

US_ANSI_ROWS = [
    [
        ("Esc", 1, "esc"), ("F1", 1, "f1"), ("F2", 1, "f2"), ("F3", 1, "f3"),
        ("F4", 1, "f4"), ("F5", 1, "f5"), ("F6", 1, "f6"), ("F7", 1, "f7"),
        ("F8", 1, "f8"), ("F9", 1, "f9"), ("F10", 1, "f10"), ("F11", 1, "f11"),
        ("F12", 1, "f12"), ("Del", 1, None),
    ],
    [
        ("`", 1, None), ("1", 1, "1"), ("2", 1, "2"), ("3", 1, "3"),
        ("4", 1, "4"), ("5", 1, "5"), ("6", 1, "6"), ("7", 1, "7"),
        ("8", 1, "8"), ("9", 1, "9"), ("0", 1, "0"), ("-", 1, None),
        ("=", 1, None), ("Bksp", 2, None),
    ],
    [
        ("Tab", 1.5, "tab"), ("Q", 1, "q"), ("W", 1, "w"), ("E", 1, "e"),
        ("R", 1, "r"), ("T", 1, "t"), ("Y", 1, "y"), ("U", 1, "u"),
        ("I", 1, "i"), ("O", 1, "o"), ("P", 1, "p"), ("[", 1, None),
        ("]", 1, None), ("\\", 1.5, None),
    ],
    [
        ("Caps", 1.75, "caps"), ("A", 1, "a"), ("S", 1, "s"), ("D", 1, "d"),
        ("F", 1, "f"), ("G", 1, "g"), ("H", 1, "h"), ("J", 1, "j"),
        ("K", 1, "k"), ("L", 1, "l"), (";", 1, ";"), ("'", 1, None),
        ("Enter", 2.25, None),
    ],
    [
        ("Shift", 2.25, "lsft"), ("Z", 1, "z"), ("X", 1, "x"),
        ("C", 1, "c"), ("V", 1, "v"), ("B", 1, "b"), ("N", 1, "n"),
        ("M", 1, "m"), (",", 1, ","), (".", 1, None), ("/", 1, None),
        ("Shift", 2.75, "rsft"),
    ],
    [
        ("Ctrl", 1.25, "lctrl"), ("Fn", 1, None), ("Super", 1.25, "super"),
        ("Alt", 1.25, "lalt"), ("Space", 6.25, "spc"), ("AltGr", 1.25, "altgr"),
        ("Ctrl", 1.25, "rctrl"),
    ],
]

GEOMETRIES = {"pt": PT_ISO_ROWS, "us": US_ANSI_ROWS}


def board_has(rows, key):
    return any(k == key for row in rows for _, _, k in row)


# ---------------------------------------------------------------------------
# Views — match gisnix's shipped defaults exactly: emailScript/clipboardHolds/
# aercLayer are all off unless a caller opts in, but herdrKey ships ON (see
# kanata-keyboard.nix), so this script draws the base layer (home-row mods +
# the default bracket chords), the navigation layer, and the herdr layer.


def base_view(rows):
    activators = [k for k in ("spc", "menu", "caps") if board_has(rows, k)]
    names = {"spc": "Space", "menu": "Menu", "caps": "Caps"}
    return {
        "title": "Base layer — home-row mods and the default bracket chords",
        "background_key": TEAL,
        "colours": {
            # Super = green, Alt = blue, Ctrl = red, Shift = amber; each
            # shared by the physical key and its two GACS home-row holds.
            "a": GREEN, ";": GREEN, "super": GREEN,
            "s": BLUE, "l": BLUE, "lalt": BLUE, "altgr": BLUE,
            "d": RED, "k": RED, "lctrl": RED, "rctrl": RED,
            "f": AMBER, "j": AMBER, "lsft": AMBER, "rsft": AMBER,
            **{k: PINK for k in activators},
            "q": GRAY, "w": GRAY, "o": GRAY, "p": GRAY,
            "x": GRAY, "z": GRAY, "m": GRAY, ",": GRAY,
        },
        "sublabels": {
            "a": "Super", "s": "Alt", "d": "Ctrl", "f": "Shift",
            "j": "Shift", "k": "Ctrl", "l": "Alt", ";": "Super",
            "super": "Super", "lctrl": "Ctrl", "rctrl": "Ctrl",
            "lalt": "Alt", "altgr": "Alt", "lsft": "Shift", "rsft": "Shift",
            "q": "{", "w": "{", "o": "}", "p": "}",
            "x": "<", "z": "<", "m": ">", ",": ">",
            "spc": "hold: nav", "menu": "hold: nav", "caps": "hold: herdr",
        },
        "legend": [
            (GREEN, "Super (a ; + Super key)"),
            (BLUE, "Alt (s l + Alt/AltGr)"),
            (RED, "Ctrl (d k + Ctrl keys)"),
            (AMBER, "Shift (f j + Shift keys)"),
            (PINK, "layer activators, held (" + ", ".join(names[k] for k in activators) + ")"),
            (GRAY, "bracket chords (also on a s / l k — see the key labels above)"),
            (TEAL, "plain key"),
        ],
    }


def nav_view(rows):
    held = [k for k in ("spc", "menu") if board_has(rows, k)]
    names = {"spc": "Space", "menu": "Menu"}
    return {
        "title": "Navigation layer — while " + " or ".join(names[k] for k in held) + " is held",
        "background_key": DARK,
        "colours": {
            "h": BLUE, "j": BLUE, "k": BLUE, "l": BLUE,
            "e": GREEN, "s": GREEN, "d": GREEN, "f": GREEN,
            "w": AMBER, "r": CYAN,
            "t": VIOLET, "g": VIOLET,
            **{k: PINK for k in held},
        },
        "sublabels": {
            "h": "←", "j": "↓", "k": "↑", "l": "→",
            "e": "ptr ↑", "s": "ptr ←", "d": "ptr ↓", "f": "ptr →",
            "w": "L-click", "r": "R-click", "t": "scr ↑", "g": "scr ↓",
            **{k: "(held)" for k in held},
        },
        "legend": [
            (BLUE, "movement (hjkl + arrows)"),
            (GREEN, "mouse pointer (e s d f)"),
            (AMBER, "left click (w)"),
            (CYAN, "right click (r)"),
            (VIOLET, "scroll (t g)"),
            (PINK, "activator (held)"),
            (DARK, "inactive"),
        ],
    }


def herdr_view(rows):
    held = [k for k in ("caps",) if board_has(rows, k)]
    return {
        "title": "herdr layer — while Caps Lock is held",
        "background_key": DARK,
        "colours": {
            "h": BLUE, "j": BLUE, "k": BLUE, "l": BLUE,
            "u": GREEN, "i": GREEN,
            "n": AMBER,
            "e": GRAY,
            **{k: PINK for k in held},
        },
        "sublabels": {
            "h": "tab ←", "l": "tab →", "j": "ws ↓", "k": "ws ↑",
            "u": "agent ↓", "i": "agent ↑",
            "n": "new tab",
            "e": "email (opt-in)",
            **{k: "(held)" for k in held},
        },
        "legend": [
            (BLUE, "tabs / workspaces (h l / j k)"),
            (GREEN, "agent list (u i)"),
            (AMBER, "new tab (n)"),
            (GRAY, "email — silent until kartoza.userEmails is set (e)"),
            (PINK, "activator (held)"),
            (DARK, "inactive"),
        ],
    }


def luminance(colour):
    r, g, b = (int(colour[i : i + 2], 16) for i in (1, 3, 5))
    return 0.299 * r + 0.587 * g + 0.114 * b


def render(view, rows, out_path):
    max_units = max(sum(u for _, u, _ in row) + (len(row) - 1) * GAP / UNIT for row in rows)
    width = int(max_units * UNIT + 2 * 40 + 80)
    height = 40 + len(rows) * (UNIT + GAP) + 120
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" '
        f'height="{height}" viewBox="0 0 {width} {height}" '
        f'font-family="Ubuntu, DejaVu Sans, sans-serif">',
        f'<rect width="{width}" height="{height}" rx="14" fill="{BG}"/>',
        f'<text x="{width / 2}" y="30" text-anchor="middle" fill="{TEXT}" '
        f'font-size="17" font-weight="bold">{escape(view["title"])}</text>',
    ]
    y = 46
    for row in rows:
        x = 40.0
        for label, units, key in row:
            w = units * UNIT + (units - 1) * GAP
            colour = view["colours"].get(key, view["background_key"])
            fg = "#1B1C1C" if luminance(colour) > 120 else TEXT
            parts.append(
                f'<rect x="{x:.1f}" y="{y}" width="{w:.1f}" height="{UNIT}" '
                f'rx="8" fill="{colour}" stroke="{PANEL}" stroke-width="1.5"/>'
            )
            label = escape(label)
            sub = view["sublabels"].get(key)
            sub = escape(sub) if sub else sub
            if sub:
                parts.append(
                    f'<text x="{x + w / 2:.1f}" y="{y + 22}" text-anchor="middle" '
                    f'fill="{fg}" font-size="13" font-weight="bold">{label}</text>'
                )
                parts.append(
                    f'<text x="{x + w / 2:.1f}" y="{y + 40}" text-anchor="middle" '
                    f'fill="{fg}" font-size="10">{sub}</text>'
                )
            else:
                parts.append(
                    f'<text x="{x + w / 2:.1f}" y="{y + UNIT / 2 + 5:.1f}" '
                    f'text-anchor="middle" fill="{fg}" font-size="13">{label}</text>'
                )
            x += w + GAP
        y += UNIT + GAP
    # legend — wraps to a new line when it would overrun the panel width
    x = 40.0
    y += 14
    for colour, text in view["legend"]:
        est = 16 + 8 + len(text) * 6.4 + 18
        if x + est > width - 40:
            x = 40.0
            y += 24
        parts.append(
            f'<rect x="{x:.1f}" y="{y}" width="16" height="16" rx="4" '
            f'fill="{colour}"/>'
        )
        parts.append(
            f'<text x="{x + 22:.1f}" y="{y + 13}" fill="{TEXT}" '
            f'font-size="11.5">{escape(text)}</text>'
        )
        x += est
    parts.append("</svg>")
    out_path.write_text("\n".join(parts) + "\n")
    print(f"wrote {out_path.relative_to(ROOT)}")


def generate_layout(layout):
    rows = GEOMETRIES[layout]
    out_dir = ROOT / "docs" / "assets" / "keyboards"
    out_dir.mkdir(parents=True, exist_ok=True)
    prefix = f"{layout}-keyboard"
    render(base_view(rows), rows, out_dir / f"{prefix}-base-layer.svg")
    render(nav_view(rows), rows, out_dir / f"{prefix}-nav-layer.svg")
    render(herdr_view(rows), rows, out_dir / f"{prefix}-herdr-layer.svg")


def main():
    for layout in GEOMETRIES:
        generate_layout(layout)


if __name__ == "__main__":
    main()
