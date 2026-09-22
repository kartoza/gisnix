# Keyboard remapping

gisnix ships one keyboard layer built on [kanata](https://github.com/jtroo/kanata), a
userspace remapper that reads raw keyboard events and rewrites them before
X11/Wayland ever sees them. It applies to every keyboard on the machine —
there is nothing to configure per board unless you plug in something with
a genuinely different physical layout (see [Adding a second keyboard](#adding-a-second-keyboard)
below).

It ships in the `services-device-input-kanata` bundle, which is on by
default — every gisnix install gets it unless you remove the line from
`hosts/<name>/config.nix`. It needs no vendor hardware and is a separate
bundle from `services-device-input` (Bazecor, OpenRazer, Piper), which
stays opt-in.

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

## Bracket chords

Press two adjacent keys together — a genuine press-together within 40ms,
not a fast roll — and you get a bracket instead of two letters.

| Chord | Types |
|---|---|
| `q`+`w` | `{` |
| `o`+`p` | `}` |
| `a`+`s` | `[` |
| `l`+`k` | `]` |
| `x`+`z` | `<` |
| `m`+`,` | `>` |

`a`+`s` and `l`+`k` double as home-row mods (Super/Alt, Shift/Ctrl) — press
them more than 40ms apart, which is how you'd normally hold a modifier
anyway, and they behave exactly as the mod table above describes. Only a
genuine press-together inside the window fires the bracket.

The chord *lines* live in `chords-us.kbd` / `chords-pt.kbd` next to
`kanata-keyboard.nix`, which picks between them by the host's
`kanataLayout`. What does **not** ship is the other kind of chord kanata
supports — bigram-to-word expansion, where typing `io` fires a macro that
finishes it as `ion` — because that fires mid-word, on ordinary typing, and
is exactly the kind of surprise a shared default should not spring on
someone. Pass your own `expansionsFile` to `kanata-config.nix` if you want
it — there's no built-in set to turn on.

## Clipboard holds

Hold `x`, `c`, or `v` instead of tapping it, and you get cut, copy, or
paste. Tap normally and you still get the letter.

| Key | Tap | Hold |
|---|---|---|
| `x` | x | Ctrl+X (cut) |
| `c` | c | Ctrl+C (copy) |
| `v` | v | Ctrl+Shift+V (paste) |

Paste is Ctrl+Shift+V, not the more common Ctrl+V, because Ctrl+Shift+V
works in a terminal and plain Ctrl+V doesn't. Cut and copy keep their
ordinary bindings, so holding `c` in a terminal still sends SIGINT via
Ctrl+C, same as tapping it always has.

## Navigation layer

Hold Space and the layout underneath your left hand becomes a mouse; your
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

Release Space or Menu and the layer disappears; every key underneath goes
back to typing normally.

## Push-to-talk (voxtype)

Hold the Menu key (between right Alt and right Ctrl on most boards —
sometimes labelled with a small menu icon) and speak; release it and
whatever you said gets typed at your cursor. This is
[voxtype](https://github.com/peteonrails/voxtype), installed and running
by default alongside kanata.

Not every board has a Menu key — the Framework 16's built-in keyboard is
one that doesn't. **Physical right Ctrl works too**, as a second trigger:
hold it and speak, same as Menu. Tapping it still sends a normal Ctrl
press, so it stays usable as a modifier — but a fast `Ctrl+<key>` chord
typed *specifically* through the right Ctrl key can be read as a hold
instead (another key pressed while it's down), which starts push-to-talk
rather than applying the modifier. Left Ctrl is untouched, so every
shortcut still works through that key; only the right one changed
character, in exchange for push-to-talk existing on boards with no Menu
key at all.

Transcription runs entirely on the machine, via whisper.cpp — nothing you
say is sent anywhere once it's running (voxtype also supports sending
audio to a remote API, but gisnix doesn't configure that mode, so it's
never in play here). The speech model itself (`base.en`) is fetched once,
the first time the machine has network after install — a
`voxtype-model-loader` service downloads it before the daemon starts, so
holding Menu on a machine that has never been online yet does nothing
until that finishes. After the model is cached on disk, everything is
offline, including on future boots with no network at all.

A tap of Menu still opens the context menu, and a tap of right Ctrl still
sends Ctrl, unchanged — only the *hold* was repurposed for this, on
either key.

A short sound plays on press (recording started) and a different one on
release (recording stopped) — audible confirmation you don't have to
watch the screen for, and a clear signal for when it's *not* recording
(no sound on press means the daemon isn't running — see below).

If nothing happens when you hold Menu or right Ctrl, check both services:

```
systemctl --user status voxtype-model-loader
systemctl --user status voxtype
```

A `voxtype-model-loader` stuck as `activating` (or restarting) means it's
still waiting on the network, or waiting on it to come back — it retries
every 30 seconds. `voxtype` itself won't start clean until the loader has
finished at least once.

See voxtype's own [configuration
reference](https://github.com/peteonrails/voxtype) for changing the
speech model, language, or output behaviour — gisnix ships it with
upstream's defaults.

## herdr layer

Hold Caps Lock and hjkl drive `herdr`. The `base` bundle installs herdr on
every machine, so this layer is there with nothing to turn on. A tap still
toggles Caps Lock as normal.

| Key | Action |
|---|---|
| `h` | previous tab |
| `l` | next tab |
| `j` | next workspace |
| `k` | previous workspace |
| `u` | down the agent list |
| `i` | up the agent list |
| `n` | new tab |
| `s` | edit scrollback — opens the pane's history in `$EDITOR` for keyboard-only selection and copy |
| `r` | toggle kanata's own macro recorder (not herdr's) — press once to start, again to stop; a click plays either way |
| `p` | play back the recorded macro |
| `e` | types your email address, if you've set one (see below) |

herdr's own `previous agent`/`next agent` binds ship unbound; the `base`
bundle's `dotfiles/herdr/config.toml` binds them to prefix+u and prefix+i
so `u`/`i` above have something to send. Leave that file alone if you
touch this layer — it is herdr's contract, read once at startup.

### The email key

`e` is silent until you tell it whose keyboard this is. Add a line to your
own user file:

```nix
# users/tim.nix
kartoza.userEmails.tim = "tim@example.com";
```

Rebuild, and holding Caps and pressing `e` types that address. Nothing is
hardcoded per machine: the key resolves the *active login session* to a
username at press time, then looks that username up in
`kartoza.userEmails` — so on a shared machine, `tim`'s hold types
`tim@example.com` and `alice`'s hold types whatever *she* set in
`users/alice.nix`, from the same physical key. An account with no entry
here gets silence when `e` is pressed.

Unmapped characters refuse rather than guess: the generated script only
emits keycodes for `a-z`, `0-9`, `.`, `@`, and `-`, so an email address
using anything else won't type at all rather than typing something close
but wrong. `@` and `-` sit on different physical keys under `us` vs `pt`,
and the script picks the right one from `kanataLayout`.

What is **not** here by default: an aerc (mail client) macro set —
compose, reply, file to folders, contacts. gisnix does not install aerc,
so this stays a separate opt-in (`kartoza.kanata.aercLayer = true;`) for
a host that actually runs it, rather than shipping mail-client keybinds
to everyone by default.

### aerc mode (opt-in)

A host with `kartoza.kanata.aercLayer = true;` gets a second thing the
herdr trigger key can reach: hold it, and — instead of herdr — you get
aerc commands on the same hjkl-shaped layout (switch account, switch
folder, file to spam/archive, compose, reply-all, and more).

Which one holding the trigger key reaches is a persistent choice, not
something you pick each time: hold the trigger key, tap Space while
still holding it, and release — that's the toggle. It doesn't change
anything about the *current* hold; it changes which layer the trigger
key reaches the *next* time you hold it, and plays a short beep so the
switch has feedback beyond memory. Toggle again (same gesture, from
inside the other layer) to go back.

This replaced an earlier design where aerc lived on its own Tab hold —
sharing the trigger key with a manual toggle means one key to remember
instead of two, at the cost of that key doing different things
depending on state.

## Layout diagrams

The tables above, drawn out. One diagram set per `kanataLayout` value —
US ANSI (the default) and pt-PT ISO — regenerated straight from the same
key tables `kanata-config.nix` uses, with `gisnix keyboard-diagrams`.

=== "US (default)"

    ![US base layer](../assets/keyboards/us-keyboard-base-layer.svg)
    ![US navigation layer](../assets/keyboards/us-keyboard-nav-layer.svg)
    ![US herdr layer](../assets/keyboards/us-keyboard-herdr-layer.svg)

=== "pt-PT"

    ![pt-PT base layer](../assets/keyboards/pt-keyboard-base-layer.svg)
    ![pt-PT navigation layer](../assets/keyboards/pt-keyboard-nav-layer.svg)
    ![pt-PT herdr layer](../assets/keyboards/pt-keyboard-herdr-layer.svg)

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

The default instance matches every keyboard on the system, so a second
ordinary, row-staggered board picks up the same home-row mods and
navigation layer as the first the moment you plug it in.

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
