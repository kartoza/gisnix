"""gisnix-installer — the Kartoza-branded bootable-USB installer.

A Textual wizard that partitions a disk (disko), writes a new host/user
config, generates a tiny per-machine flake pinning gisnix, and runs
nixos-install. Software selection installs the fixed default bundle set
(base + minimal COSMIC) rather than opening `gisnix configure`'s own
bundle chooser in-process — that chooser is itself a Textual App, and
nesting one `asyncio.run()` inside another crashes. Pick anything else
with `gisnix configure` once the machine is up.
"""
