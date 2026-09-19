# Keyboard remapping

gisnix ships one keyboard layer built on [kanata](https://github.com/jtroo/kanata), a
userspace remapper that reads raw keyboard events and rewrites them before
X11/Wayland ever sees them. It applies to every keyboard on the machine —
there is nothing to configure per board unless you plug in something with
a genuinely different physical layout (see [Adding a second keyboard](#adding-a-second-keyboard)
below).

Enable it with the `services-device-input` bundle. It is not on by
default; add the line to `hosts/<name>/config.nix` and rebuild.

## Home-row modifiers

Tap a home-row key and it types the letter. Hold it past 500ms and it
becomes a modifier instead. Hold two together and they stack.

| Key | Tap | Hold |
|---|---|---|
| `a` | a | Super |
| `s` | s | Alt |
| `d` | d | Ctrl |
| `f` | f | Shift |
| `j` | j | Shift |
| `k` | k | Ctrl |
| `l` | l | Alt |
| `;` | ; | Super |

Holding `d` and `f` together, for instance, gives you Ctrl+Shift — the two
modifiers combine the same way pressing two physical modifier keys would.
A held modifier applies to whatever key you press next on either hand, so
"hold d, tap c" is Ctrl+C.

The 500ms hold window is deliberate: it is well past the length of an
ordinary keystroke, so nothing you type in the normal course of typing
gets mistaken for a modifier. If you find yourself typing fast enough to
trip it — or slow enough that a real hold feels sluggish — the timeout is
`modHoldTimeout` in `kanata-config.nix`.

## Navigation layer

Hold Space or the Menu key (to the left of the right Ctrl key on most
boards) and the layout underneath your left hand becomes a mouse; your
right hand becomes arrow keys and paging.

| Key | Action |
|---|---|
| `e` | mouse up |
| `s` | mouse left |
| `d` | mouse down |
| `f` | mouse right |
| `w` | left click |
| `r` | right click |
| `t` | scroll up |
| `g` | scroll down |
| `h j k l` | left / down / up / right (arrow keys) |
| `n` | Home |
| `u` | Page Down |
| `i` | Page Up |
| `o` | End |
| `m`, `,`, `.` | mouse speed: half, quarter, tenth |

Release Space or Menu and the layer disappears; every key underneath
reverts to typing normally. This is a hold, not a toggle — there is
nothing to switch back.

## What is NOT included

The chord system — pressing two keys together to fire a macro, used
elsewhere for bracket typing (`{`, `}`, `[`, `]`) — ships disabled. Write
your own chord file and pass it to `kanata-config.nix`'s `chordsFile`
argument if you want one; there is no default set. Two files, `chordsFile`
and `expansionsFile`, exist for exactly this — see the comments in
`software/services/device/input/kanata-config.nix` for the format.

## Toggling it off

```
kanata-toggle    # disable/re-enable remapping for every kanata instance
kanata-status    # which instances are running
kanata-debug     # service status, input devices, recent logs
```

A raw, unremapped keyboard is sometimes what you want — troubleshooting a
game that reads raw scancodes, or handing the machine to someone who
doesn't use this layout. `kanata-toggle` stops the daemon; the physical
keyboard reverts to whatever it would type without it, and toggling again
turns it back on.

## Adding a second keyboard

The default instance matches every keyboard on the system — plug in a
second, ordinary, row-staggered board and it gets the same home-row mods
and navigation layer as the first automatically. You do not need to do
anything.

Write a *separate* kanata instance only when a board's physical layout
doesn't match a standard keyboard closely enough for the shared layer to
make sense on it — an ortholinear or split board, one you want to keep at
its factory layout, or one that should carry its own chord set. Run:

```
gisnix add-keyboard
```

It lists connected keyboards with their device paths and prints a
`services.kanata.keyboards.<name>` block scoped to the one you pick, ready
to paste into your host's own configuration.
