---
hide:
  - toc
---

<span class="kz-eyebrow">DESIGN</span>

# Why gisnix

gisnix is a NixOS distribution built for one kind of machine: a geospatial
workstation. It is opinionated on purpose. Where a general-purpose distro
hands you a menu and a shrug, gisnix has already made most of the choices —
the ones that a working GIS professional would otherwise spend a weekend
making, then remaking on the next machine. What it keeps configurable, it
keeps configurable deliberately, in one flake, with one command.

This page is the long version of what that means.

## GIS-centred, and open source about it

The distribution is organised around QGIS and the geospatial stack, not
around a general desktop that happens to have QGIS available in it. The
current QGIS release channels are here, and so are **23 pinned historical
QGIS releases** going back to 1.8 — each built from its own pinned nixpkgs,
so an old version and a current one can sit on the same machine without
fighting over shared library versions. A project that needs QGIS 3.28 to
reproduce a client's exact output does not force the whole workstation back
to 2022.

Everything in gisnix is open source, and buildable from source. The ISO
itself is one `nix build` away; nothing about the distribution is a binary
you have to take on trust.

## Opinionated, in a way you can override

gisnix ships one desktop, one storage default, one keyboard philosophy and
one way of describing a machine. That is the opinion. The escape hatch is
that all of it is declarative — every choice is a line in a flake you own,
so disagreeing with gisnix is editing a file and rebuilding, not fighting
the distribution. The defaults are a starting point that already works, not
a cage.

## Software as bundles, not a package list

Software is organised into **bundles** — named sets under `software/`, each
with a `bundle.json` describing what it is and what it depends on. You do
not manage a flat list of packages; you say `desktop-gis` and the desktop it
needs to run in comes with it, because the bundle declares that dependency.
`gisnix configure` gives you a menu over the whole catalogue and writes your
answers back to one file. A bundle is the unit of "I want this capability",
and the machinery works out the packages.

[Software bundles →](admin/software-bundles.md)

## COSMIC on Wayland

The desktop is **COSMIC**, System76's Rust compositor, running on Wayland.
One desktop, tracked close to upstream — not three half-maintained ones. It
is a modern, GPU-accelerated, tiling-capable environment rather than a
museum piece kept alive for compatibility, and it is the same on every
gisnix machine, so muscle memory moves with you.

## ZFS, encrypted by default

The installer's default layout is **ZFS on a single disk with AES-256-GCM
encryption** — a passphrase prompted at boot, the disk unreadable without
it. ZFS is not incidental here: it is what makes the snapshots,
send/receive backups, checksummed integrity and instant rollbacks real.
Plain XFS and multi-disk ZFS (stripe, RAIDZ, RAIDZ2) are there for machines
that want them, but the encrypted-single-disk default is the one a field
laptop with client data on it should be running.

[Storage modes →](admin/storage-modes.md)

## Keyboard-centric: kanata, and speech where a key would be

gisnix treats the keyboard as the primary instrument. **kanata** is on by
default: home-row modifiers, a navigation layer, chords — the ergonomics
that keep your hands on the home row instead of reaching for arrow keys and
a mouse. It needs no vendor hardware; it is a software remap that works on a
laptop's built-in keyboard as readily as on a split ergonomic board.

Held on top of that is **voxtype push-to-talk speech-to-text**: hold the
Menu key and talk, and the transcription lands wherever your cursor is —
any application, any text field, no per-app integration. Speech is wired in
as just another key kanata knows how to hold, so it is available everywhere
the keyboard is.

[Keyboard remapping →](user/keyboard.md)

## LLM tools, each in a jail

The AI assistants gisnix ships — Claude Code, Gemini CLI, OpenCode, a
local Ollama workspace — each run **inside a bubblewrap sandbox**. The point
is blunt: an LLM agent runs code and reads files on your behalf, and a
compromised or over-eager one should not be able to reach your SSH agent,
your keys, or the rest of your home directory. The sandbox draws that line.
The local-LLM workspace goes further and runs the model server, its weights
and the agent together in one jail that shares only a loopback network, so
the agent can reach the model without either being able to see your files.

This is opt-in — the bundle pulls a real stack into the closure — but when
you take it, the isolation is the default, not a flag you have to remember.

## One flake, reproducible, with real rollbacks

A gisnix machine is one flake. Rebuild it and you get a new generation,
selectable from the bootloader menu; the change is whole-system and
reproducible, never a half-applied state. Roll back by picking the previous
generation at boot. The same flake builds a VM of the machine for testing,
and the same `nix build` produces the installer ISO. Reproducibility is not
a slogan here — it is the reason the distribution is shaped the way it is.

## Locale that travels with you

A machine picks one locale preset — keyboard, timezone, language and
regional formatting as a single choice from a library covering the major
GIS-using countries, in both native-language and English-desktop variants.
But the three axes come apart when you need them to: `gisnix locale` lets
you keep your language and number formatting while moving just the clock, so
a week in Zurich is one command, and coming home is one more.

## Built to be built on

gisnix exposes `lib.mkHost`. A separate flake can pin gisnix and build its
own machines against gisnix's bundles, profiles and overlays while keeping
only its own host and user files — a few lines, not a fork. Your fleet stays
yours; the distribution underneath it stays gisnix.

[Building on gisnix →](developer/downstream-flakes.md)

---

<div class="kz-cta" markdown>
[:material-download: Download the ISO](https://github.com/kartoza/gisnix/releases/latest/download/gisnix-installer.iso){ .kz-cta__primary }
[:material-book-open-variant: Quickstart](user/quickstart.md){ .kz-cta__secondary }
</div>

Made with 💗 by [Kartoza](https://kartoza.com) | [Donate!](https://github.com/sponsors/timlinux) | [GitHub](https://github.com/kartoza/gisnix)
