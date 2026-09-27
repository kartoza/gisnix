# Supported hardware

gisnix is NixOS underneath, and NixOS runs on an enormous range of machines.
What gisnix adds on top — the desktop, the disk layout, the keyboard work, the
installer — is developed and tested on a small number of laptops. On those, an
install is a known quantity. On everything else it will very often work, but it
is worth knowing where the well-trodden path ends.

The installer is **x86_64 (64-bit Intel/AMD) only** for now. Apple Silicon and
other ARM machines are not yet supported.

## Where it is well tested

The day-to-day development machines are Framework laptops, so these get the
most attention and are the safest bet:

| Laptop | Notes |
| --- | --- |
| **Framework Laptop 16** | The primary development machine. Everything here — install, desktop, suspend/resume, keyboard, Wi-Fi — is exercised on it regularly. |
| **Framework Laptop 14** | Also regularly used and installed. |

If you are buying a machine specifically to run gisnix, a Framework is the
choice that will give you the least trouble.

## Everywhere else — your mileage may vary

On other laptops and desktops gisnix usually installs and runs fine, but it is
not something we can promise for hardware we have never seen. The parts most
likely to need attention are the ones that vary most between machines:

- **Wi-Fi adapters.** This is the single most common sticking point. Some
  radios need a firmware blob the installer does not carry, or a kernel newer
  than the one on the ISO, or a driver that behaves differently on brand-new
  silicon. If your Wi-Fi does not appear in the installer, that is almost
  always why.
- **Very new or unusual hardware** — bleeding-edge chipsets, exotic GPUs,
  fingerprint readers, oddball trackpads. NixOS support for these arrives over
  time; a machine released last month may need a newer kernel than the release
  you are installing.
- **Proprietary vendor gadgetry** that only ever shipped a Windows driver.

None of this means gisnix *won't* run — plenty of non-Framework machines run
it happily. It means that if something is going to need a hand, this is where
it will be, and you should be comfortable reading a log and filing an issue.

!!! tip "No Wi-Fi in the installer? You are not stuck"
    If your wireless adapter does not show up in `nmtui`, you do not have to
    give up on the install. Use a **wired connection** if you have one, or
    **tether an iPhone over USB** (below) to get online long enough to install.
    Once installed, a newer gisnix — or a per-host kernel pin in your
    `hardware.nix` — will often bring the adapter to life. Please
    [open an issue](https://github.com/kartoza/gisnix/issues) with your
    adapter (`lspci -nnk`) so it can be looked at.

## Tethering from an iPhone

You do not need Wi-Fi or a cable to the wall to install gisnix — a phone is
enough. iPhone USB tethering works **out of the box**, on both the installer
and the installed machine, with nothing to set up:

1. Plug the iPhone into the machine with a USB cable.
2. On the phone, turn on **Settings → Personal Hotspot**.
3. When the phone asks, tap **Trust This Computer**.
4. The phone appears as a wired network. In `sudo nmtui` (or the desktop's
   network menu once installed), activate that connection.

The pairing service this relies on (`usbmuxd`) is already running, which is
what lets the phone become a network interface rather than sitting forever at
"Trust This Computer?". It is the reliable fallback when a laptop's own Wi-Fi
is the very thing that is not working yet.

Android USB tethering also generally works, since it presents a standard USB
network device; it just does not need the iPhone pairing service.
