#!/usr/bin/env python3
"""Tray icon showing which of herdr/aerc/obs the kanata trigger key
currently reaches — H, A, or O — by following the same TCP layer-change
feed hosts/abyss/kanata-keyboard.nix's razer-layer-lights already listens
to (see kanata-config.nix's `modes`/`nextMode` for the herdr -> aerc ->
obs -> herdr cycle this is showing).

    kanata-layer-indicator --listen 127.0.0.1:5829

Generic — works on any gisnix host running kanata with a TCP port
configured, not Razer-hardware-specific like razer-layer-lights, which is
why this lives in gisnix rather than a host's own private dotfiles.

Read-only: kanata's TCP server only ever broadcasts events, there is no
reply channel to send it anything — so this is purely an at-a-glance
display, not a way to force a mode switch from the tray.
"""

import argparse
import glob
import json
import os
import socket
import threading
import time

import pystray
from PIL import Image, ImageDraw, ImageFont

# The three BASE layers the cycle rotates between (kanata-config.nix's
# `modes`) — the ones that persist between trigger-key holds, as opposed
# to "herdr"/"aerc"/"obs" themselves, which only exist for the instant the
# trigger key is actually down. Everything else kanata reports
# (navigation, meta, the held layers) is ignored: it doesn't change which
# mode the NEXT hold reaches, so the icon has no reason to change either.
MODE_LABEL = {
    "default-herdr": "H",
    "default-aerc": "A",
    "default-obs": "O",
}

ICON_SIZE = 64
BG_COLOR = (40, 44, 52, 255)
FG_COLOR = (255, 255, 255, 255)


def find_font(size):
    for pattern in ("*Black*.ttf", "*Bold*.ttf", "*.ttf"):
        matches = glob.glob(os.path.join(os.environ.get("LATO_DIR", ""), "**", pattern), recursive=True)
        if matches:
            return ImageFont.truetype(matches[0], size)
    return ImageFont.load_default()


def make_icon(label):
    img = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), BG_COLOR)
    draw = ImageDraw.Draw(img)
    font = find_font(int(ICON_SIZE * 0.62))
    bbox = draw.textbbox((0, 0), label, font=font)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text(((ICON_SIZE - w) / 2 - bbox[0], (ICON_SIZE - h) / 2 - bbox[1]), label, font=font, fill=FG_COLOR)
    return img


def listen(icon, host, port):
    """Mirrors razer-layer-lights.py's own reconnect-on-drop loop: kanata
    may not be up yet, or may restart (e.g. powerManagement.resumeCommands
    on abyss) — reconnect rather than give up."""
    current = "default-herdr"
    while True:
        try:
            with socket.create_connection((host, port), timeout=None) as sock:
                buffer = b""
                while True:
                    chunk = sock.recv(4096)
                    if not chunk:
                        break
                    buffer += chunk
                    while b"\n" in buffer:
                        line, buffer = buffer.split(b"\n", 1)
                        try:
                            event = json.loads(line)
                        except json.JSONDecodeError:
                            continue
                        layer = event.get("LayerChange", {}).get("new")
                        if layer in MODE_LABEL and layer != current:
                            current = layer
                            icon.icon = make_icon(MODE_LABEL[current])
                            icon.title = f"kanata mode: {MODE_LABEL[current]}"
        except OSError:
            pass
        time.sleep(2)  # kanata restarting / not up yet - retry


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--listen", metavar="HOST:PORT", required=True, help="kanata's TCP layer-event server")
    args = parser.parse_args()
    host, _, port = args.listen.rpartition(":")

    icon = pystray.Icon(
        "kanata-layer-indicator",
        make_icon(MODE_LABEL["default-herdr"]),
        "kanata mode: H",
        menu=pystray.Menu(
            pystray.MenuItem("H = herdr, A = aerc, O = obs", None, enabled=False),
            pystray.MenuItem("Quit", lambda: icon.stop()),
        ),
    )

    threading.Thread(target=listen, args=(icon, host or "127.0.0.1", int(port)), daemon=True).start()
    icon.run()


if __name__ == "__main__":
    main()
