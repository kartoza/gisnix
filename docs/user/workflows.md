# The workflow it unlocks

Describing a machine in a file is the visible half of gisnix. The quieter
half — and, once you have lived with it, the part that changes how you work —
is what the same idea does at the scale of a single folder, and how it changes
the loop of making a change at all.

Two tools do most of the work here. A **flake** is a self-contained
description — of a whole machine, or of just the tools one project needs.
**direnv** notices which folder you are in and loads the matching description
around you. Together they make your environment something that follows your
work rather than something you set up once and then carry everywhere.

## A toolset that follows the folder

On most systems, everything you install is installed *everywhere*. Two
projects that need different versions of the same tool are a problem you solve
by hand, and the tools you needed for last month's job are still cluttering
your shell today.

gisnix works differently. A project folder can carry its own flake — the exact
compilers, libraries, language runtimes, environment variables and command-line
tools that project needs. The moment you `cd` into the folder, direnv loads
them; the moment you leave, it takes them away again and you are back to a
clean base system. Nothing leaks in either direction.

The effect is worth spelling out:

- Each project gets precisely the tools it declares — the right versions, every
  time, on any gisnix machine, with no "works on my laptop" surprises.
- Your base system stays uncluttered. The heavy, project-specific toolchains
  live in the projects, not in your everyday shell.
- A colleague who clones the same project gets the same environment, because it
  is written down beside the code rather than kept in someone's head.

This is the same principle as the machine-in-a-file, applied one level down.
Your machine is a flake; each serious project is a flake; direnv is what makes
moving between them feel like nothing at all. Setting up a QGIS plugin, a data
pipeline or a web app becomes: open the folder, and its world is already there.

!!! note "This is already switched on"
    gisnix ships direnv wired up, and the machine's own configuration folder
    (`~/nixos-config`) is itself a flake — so `cd`-ing into it drops you into
    gisnix's tools automatically. The first time you enter a folder with a new
    `.envrc`, direnv asks you to approve it once with `direnv allow`; after
    that it is silent.

## Change by description, reviewed as a diff

The second shift is in how you make a change at all. Because the machine is a
description, changing it is editing that description and rebuilding — and
before anything is applied, gisnix can show you a **diff**: exactly what will
be added, removed or altered, in plain terms, while your running system is
still untouched. You approve a change you can see, rather than discovering
after the fact what some installer did.

That pairs naturally with the AI assistants gisnix ships (each kept in its own
[sandbox](../why.md#assistants-kept-in-a-room-of-their-own)). You can describe
what you want in ordinary words — "add this package", "turn on that service" —
let the assistant work out which lines of the description to change, and then
read the diff yourself before it is applied. The machine still only changes
when you say so, and you can always roll back to the previous generation if a
change does not sit right. The convenience of describing intent in plain
language, without giving up the safety of seeing precisely what happens.

## Where to go next

- [Understanding gisnix](../why.md) — the ideas these workflows build on.
- [After the install](after-install.md) — applying changes and pulling
  updates on a running machine.
- [Software bundles](../admin/software-bundles.md) — choosing what your
  machine carries.
