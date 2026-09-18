"""gisnix-installer — the Kartoza-branded bootable-USB installer.

A Textual wizard that partitions a disk (disko), writes a new host/user
config, generates a tiny per-machine flake pinning gisnix, and runs
nixos-install. The software-selection step is the same bundle chooser `kz
configure` uses on an already-installed machine (see
utils/lib/configure_tui.py) — one implementation, used before and after
install.
"""
