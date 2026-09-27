# Locale and timezone

A gisnix machine has one **preset locale** — a bundle that sets the keyboard
layout, timezone, system language and regional number/date formatting together,
chosen from `software/locale/`. On top of that, you can override a single axis
without changing the preset, which is what you want when only one thing needs to
move — most often the clock, while travelling.

All of these write into the host's `config.nix` and take effect on your next
`gisnix update`; nothing changes the running system until you rebuild.

## Just the clock

To change only the timezone:

```bash
gisnix set-timezone
```

It offers every Region/City the system knows (type to filter — `zurich`,
`sao_paulo`, `auckland`) and writes the choice as a `timeZone` override on this
host. Your language, keyboard and formatting are untouched.

## The whole locale

For anything beyond the clock — the preset itself, or the language and
formatting axes — use:

```bash
gisnix locale            # show current settings, then a menu
gisnix locale --show     # just print them and exit
```

The menu lets you pick a different preset, or override one axis at a time:

- **clock** — the timezone (the same picker `set-timezone` gives you).
- **language** — the desktop and system language.
- **formatting** — number, date and currency conventions.

The travelling case makes the split clear: from a `pt-en` preset (Portugal,
English desktop), override the clock to `Europe/Zurich` for a trip and leave
everything else; clear the override when you get home and the preset's
`Europe/Lisbon` returns. An override always wins over the preset for its one
axis, and clearing it hands that axis back.

Full per-flag detail is in the commands reference
([`set-timezone`](../references/commands.md#set-timezone),
[`locale`](../references/commands.md#locale)).
