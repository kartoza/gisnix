#!/usr/bin/env python3
"""Build gisnix's branded OBS scene collection over obs-websocket.

OBS's own scene-collection JSON (~/.config/obs-studio/basic/scenes/*.json) is
a versioned, UUID-keyed format meant to be written by OBS itself, not hand-
authored — so this builds each collection the same way a human clicking
through OBS's UI would: by calling obs-websocket (localhost:4455, no auth —
see obs-scenes.nix) to create scenes, sources and their transforms one at a
time. Run it with OBS already open.

    gisnix obs-setup kartoza
    gisnix obs-setup qgis
    gisnix obs-setup kartoza --force   # tear down and rebuild if it exists

Canvas is assumed 1920x1080 (OBS's own default) — every transform below is
an absolute pixel position for that size. A profile running a different
canvas will still work, just with the frame/lower-third proportions off.
"""

import argparse
import glob
import os
import socket
import sys

import obsws_python as obs

# --------------------------------------------------------------------------
# Brand palettes — sampled from the actual committed assets (resources/
# kartoza-logo.png, resources/qgis-spatial-splash.png), not invented, so the
# scenes read as the same brand as gisnix's Plymouth/GRUB boot theming.
#
# QGIS has no vendored logo (unlike Kartoza's resources/kartoza-logo.png) —
# redistributing one needs a license check gisnix hasn't done yet, so the
# QGIS brand card is a styled wordmark (text_ft2_source), not an image. Swap
# in a real logo file + an `image` element once that's cleared.
# --------------------------------------------------------------------------
BRANDS = {
    "kartoza": {
        "collection": "Kartoza",
        "bg": "#262626",
        "primary": "#EFB348",
        "secondary": "#55A3CD",
        "logo": os.environ.get("KARTOZA_LOGO", "/etc/xdg/obs-scenes/kartoza-logo.png"),
        "wordmark": None,
    },
    "qgis": {
        "collection": "QGIS",
        "bg": "#062436",
        "primary": "#4D6E2F",
        "secondary": "#62882E",
        "logo": None,
        "wordmark": "QGIS",
    },
}

CANVAS_W, CANVAS_H = 1920, 1080
BORDER = 24  # branded frame thickness, Screen/ScreenCam/ScreenOverlay

# OBS source kinds — the one thing here most likely to need adjusting on a
# given OBS build (plugin set, Wayland vs X11). First CreateInput failure
# prints `GetInputKindList`'s own output, which is the actual source of
# truth for what's available.
KIND_COLOR = "color_source_v3"
KIND_IMAGE = "image_source"
KIND_TEXT = "text_ft2_source_v2"
KIND_WEBCAM = "v4l2_input"
KIND_SCREEN = "pipewire-screencapture-source"  # portal-based — cosmic-comp has no wlr-screencopy
KIND_OVERLAY = "input-overlay"


def abgr(hex_color, alpha=255):
    """OBS color_source packs its `color` setting as 0xAABBGGRR, not ARGB —
    confirmed against OBS's own color_source.c. If a colour renders swapped
    on screen, this is the first thing to re-check."""
    h = hex_color.lstrip("#")
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return (alpha << 24) | (b << 16) | (g << 8) | r


def pick_webcam():
    """First /dev/video* that isn't obs.nix's v4l2loopback sink
    (video_nr=1, i.e. /dev/video1) — that device is OBS's own virtual-
    camera OUTPUT, not something to read a scene's webcam source from."""
    for dev in sorted(glob.glob("/dev/video*")):
        if dev != "/dev/video1":
            return dev
    return "/dev/video0"


def obs_is_running():
    """/proc scan, not pgrep — one fewer runtime dependency for a script
    that otherwise only needs the obsws-python interpreter.

    Checks cmdline, not comm: comm is the kernel's 15-char-truncated
    executable name, which on a wrapped Nix package (wrapOBS's real binary
    is typically named something like .obs-wrapped, not obs) won't match a
    plain "obs" equality check at all. cmdline is the full argv, same
    thing `pgrep -f` searches — substring, not equality, so it matches
    regardless of the exact wrapper name.
    """
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                if b"obs" in f.read():
                    return True
        except OSError:
            continue  # process exited mid-scan, or we can't read it — skip it
    return False


def port_open(host, port, timeout=2):
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def explain_unreachable(host, port):
    print(f"Can't reach OBS's websocket at {host}:{port}.", file=sys.stderr)
    if obs_is_running():
        print(
            "OBS is running, but isn't listening there yet — obs-scenes.nix's\n"
            "websocket settings only take effect from OBS's NEXT launch after a\n"
            "rebuild. Fully quit OBS (check it isn't still sitting in the tray)\n"
            "and reopen it, then run this again.",
            file=sys.stderr,
        )
    else:
        print(
            "OBS doesn't appear to be running at all. Start it, then run this\n"
            "again.",
            file=sys.stderr,
        )


class SceneBuilder:
    def __init__(self, client, scene_name):
        self.cl = client
        self.scene = scene_name
        # CreateInput's sceneName must already exist — it adds a source TO
        # a scene, it doesn't create one. CreateSceneCollection only gives
        # us ONE default scene (removed later in main() once the real ones
        # exist), so every other scene name needs its own CreateScene.
        #
        # Idempotent: a retry (crash mid-build, or a deliberate --force
        # rebuild) can find this exact scene name already here from a
        # previous run, which CreateScene refuses outright ("A source
        # already exists by that scene name"). Removing it first is safe
        # ONLY because main() guarantees a scratch scene exists before any
        # of this runs — OBS refuses to remove a collection's LAST scene,
        # and this one might well be it.
        existing = {s["sceneName"] for s in client.get_scene_list().scenes}
        if scene_name in existing:
            client.remove_scene(scene_name)
        client.create_scene(scene_name)

    def _place(self, item_id, x, y, w=None, h=None, source_w=None, source_h=None):
        t = {"positionX": float(x), "positionY": float(y)}
        if w is not None and source_w:
            t["scaleX"] = w / source_w
        if h is not None and source_h:
            t["scaleY"] = h / source_h
        self.cl.set_scene_item_transform(self.scene, item_id, t)

    def _name(self, name):
        # Inputs are named uniquely across the WHOLE collection, not per
        # scene — "A source already exists by that input name" the moment
        # a second scene tries to create its own "Background"/"Accent Bar"/
        # etc. Prefixing with the scene name is what actually scopes them.
        return f"{self.scene} {name}"

    def color(self, name, hex_color, x, y, w, h, alpha=255):
        resp = self.cl.create_input(
            self.scene, self._name(name), KIND_COLOR, {"color": abgr(hex_color, alpha), "width": w, "height": h}, True
        )
        self._place(resp.scene_item_id, x, y)
        return resp.scene_item_id

    def image(self, name, path, x, y):
        resp = self.cl.create_input(self.scene, self._name(name), KIND_IMAGE, {"file": path}, True)
        self._place(resp.scene_item_id, x, y)
        return resp.scene_item_id

    def text(self, name, text_value, color_hex, x, y, size=64, bold=True):
        settings = {
            "text": text_value,
            "color1": abgr(color_hex),
            "color2": abgr(color_hex),
            "font": {"face": "Sans Bold" if bold else "Sans", "size": size},
        }
        resp = self.cl.create_input(self.scene, self._name(name), KIND_TEXT, settings, True)
        self._place(resp.scene_item_id, x, y)
        return resp.scene_item_id

    def webcam(self, name, device, x, y, w, h):
        resp = self.cl.create_input(self.scene, self._name(name), KIND_WEBCAM, {"device_id": device}, True)
        self._place(resp.scene_item_id, x, y, w, h, source_w=CANVAS_W, source_h=CANVAS_H)
        return resp.scene_item_id

    def screencapture(self, name, x, y, w, h):
        # No source-specific settings pre-filled: the portal prompts the
        # user to pick a screen/window the first time this input runs.
        resp = self.cl.create_input(self.scene, self._name(name), KIND_SCREEN, {}, True)
        self._place(resp.scene_item_id, x, y, w, h, source_w=CANVAS_W, source_h=CANVAS_H)
        return resp.scene_item_id

    def overlay(self, name, x, y):
        # input-overlay needs its own layout (svg+xml) authored in its own
        # editor — this creates the source with none configured, so it
        # shows "no layout" until that one-time setup runs.
        resp = self.cl.create_input(self.scene, self._name(name), KIND_OVERLAY, {}, True)
        self._place(resp.scene_item_id, x, y)
        return resp.scene_item_id


def brand_mark(b, s, x, y, size=96):
    """Logo image if the brand has one, else a styled wordmark."""
    if b["logo"] and os.path.exists(b["logo"]):
        s.image("Brand Logo", b["logo"], x, y)
    else:
        s.text("Brand Wordmark", b["wordmark"] or b["collection"], b["primary"], x, y, size=size)


def build_webcam_scene(cl, b, webcam_device):
    s = SceneBuilder(cl, "Webcam")
    s.color("Background", b["bg"], 0, 0, CANVAS_W, CANVAS_H)
    s.webcam("Camera", webcam_device, 0, 0, CANVAS_W, CANVAS_H)
    s.color("Lower Third Bar", b["primary"], 0, 912, CANVAS_W, 72, alpha=230)
    s.text("Lower Third Name", "Your Name — Kartoza", "#111111", 32, 924, size=40)
    brand_mark(b, s, CANVAS_W - 220, 32, size=64)


def build_screen_scene(cl, b, name="Screen"):
    s = SceneBuilder(cl, name)
    s.color("Background", b["primary"], 0, 0, CANVAS_W, CANVAS_H)
    s.screencapture("Screen Capture", BORDER, BORDER, CANVAS_W - 2 * BORDER, CANVAS_H - 2 * BORDER)
    brand_mark(b, s, CANVAS_W - 220, CANVAS_H - 96, size=56)
    return s


def build_screencam_scene(cl, b, webcam_device):
    s = build_screen_scene(cl, b, "ScreenCam")
    pip_w, pip_h = 420, 236
    x, y = CANVAS_W - pip_w - 48, CANVAS_H - pip_h - 48
    s.color("Cam Border", b["secondary"], x - 8, y - 8, pip_w + 16, pip_h + 16)
    s.webcam("Camera PiP", webcam_device, x, y, pip_w, pip_h)


def build_screenoverlay_scene(cl, b):
    s = build_screen_scene(cl, b, "ScreenOverlay")
    s.overlay("Input Overlay", 48, CANVAS_H - 48 - 220)


def build_card_scene(cl, b, name, headline, sub):
    s = SceneBuilder(cl, name)
    s.color("Background", b["bg"], 0, 0, CANVAS_W, CANVAS_H)
    s.color("Accent Bar", b["primary"], 0, CANVAS_H - 16, CANVAS_W, 16)
    brand_mark(b, s, CANVAS_W // 2 - 110, 360, size=120)
    s.text("Headline", headline, "#FFFFFF", CANVAS_W // 2 - 260, 540, size=56)
    if sub:
        s.text("Subtext", sub, b["primary"], CANVAS_W // 2 - 260, 620, size=32, bold=False)


SCENES = ["Webcam", "Screen", "ScreenCam", "ScreenOverlay", "Intro", "BRB", "Outro"]

# Never a real scene name — exists only so OBS always has a scene to fall
# back to while every real one gets torn down and rebuilt. OBS refuses to
# leave a collection with zero scenes, so without this, rebuilding
# whichever scene happens to be the last one left would fail outright.
SCRATCH_SCENE = "_gisnix_scratch_"


def build_all(cl, b, webcam_device):
    build_webcam_scene(cl, b, webcam_device)
    build_screen_scene(cl, b)
    build_screencam_scene(cl, b, webcam_device)
    build_screenoverlay_scene(cl, b)
    build_card_scene(cl, b, "Intro", "Starting soon", "demo@kartoza.com")
    build_card_scene(cl, b, "BRB", "Be right back", None)
    build_card_scene(cl, b, "Outro", "Thanks for watching", "kartoza.com")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("brand", choices=sorted(BRANDS))
    parser.add_argument("--force", action="store_true", help="tear down and rebuild if the collection exists")
    parser.add_argument("--host", default="localhost")
    parser.add_argument("--port", type=int, default=4455)
    parser.add_argument("--password", default="")
    args = parser.parse_args()

    b = BRANDS[args.brand]

    if not port_open(args.host, args.port):
        explain_unreachable(args.host, args.port)
        sys.exit(1)

    try:
        cl = obs.ReqClient(host=args.host, port=args.port, password=args.password, timeout=5)
    except Exception as exc:  # noqa: BLE001 — port's open, so this is something else (auth, protocol) — surface it as-is
        print(f"Connected to {args.host}:{args.port} but the handshake failed: {exc}", file=sys.stderr)
        sys.exit(1)

    existing = {c for c in cl.get_scene_collection_list().scene_collections}
    if b["collection"] in existing:
        if not args.force:
            print(f"'{b['collection']}' already exists — switching to it. Pass --force to rebuild.")
            cl.set_current_scene_collection(b["collection"])
            return
        cl.set_current_scene_collection(b["collection"])
        # Not removed here: OBS refuses to leave a scene collection with
        # zero scenes, and a loop over every existing scene would hit that
        # on the last one. build_all() below creates all 7 new scenes
        # first (distinct names), then the cleanup loop at the end of
        # main() removes whatever old scenes are left over — by then
        # there's always at least 7 scenes, never zero.
    else:
        cl.create_scene_collection(b["collection"])
        # CreateSceneCollection switches into it with one default scene —
        # removed once the real scenes exist (a collection can't have zero).

    existing_scenes = {s["sceneName"] for s in cl.get_scene_list().scenes}
    if SCRATCH_SCENE not in existing_scenes:
        cl.create_scene(SCRATCH_SCENE)

    # Orphaned sources from an earlier interrupted run: RemoveScene drops
    # the scene but NOT the inputs that were in it (they just stop
    # appearing in any scene) — so a retry's CreateInput would still hit
    # "A source already exists by that input name" even after
    # SceneBuilder recreates the scene itself clean. Every input this
    # script ever creates is named "<scene> <thing>", so sweeping by that
    # prefix catches them regardless of which scene they came from or
    # whether that scene still exists.
    existing_inputs = [i["inputName"] for i in cl.get_input_list().inputs]
    prefixes = tuple(f"{scene} " for scene in SCENES)
    for input_name in existing_inputs:
        if input_name.startswith(prefixes):
            cl.remove_input(input_name)

    webcam_device = pick_webcam()
    print(f"Webcam device: {webcam_device}")
    build_all(cl, b, webcam_device)

    for scene in cl.get_scene_list().scenes:
        if scene["sceneName"] not in SCENES:
            cl.remove_scene(scene["sceneName"])

    cl.set_current_program_scene("Screen")
    print(f"'{b['collection']}' built: {', '.join(SCENES)}")


if __name__ == "__main__":
    main()
