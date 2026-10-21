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

No visual QA happened on any of this beyond reading it back as numbers —
nothing here renders OBS, so there's no way to screenshot the result from
where this runs. The geometry (especially the slant panel's rotation) is a
best-effort calculation, not a pixel-verified one; nudge it by hand in OBS's
own Edit Transform dialog if an angle or gap looks wrong.
"""

import argparse
import glob
import json
import os
import pwd
import socket
import subprocess
import sys

import obsws_python as obs
from obsws_python.error import OBSSDKRequestError

# --------------------------------------------------------------------------
# Brand palette. gisnix ships exactly one brand outright — QGIS, fully
# public: no vendored logo (redistributing one needs a license check
# gisnix hasn't done), so it's a styled wordmark (text_ft2_source), and its
# tones are sampled from the real committed asset
# (resources/qgis-spatial-splash.png), not invented.
#
# Every other brand — Kartoza included — is NOT defined here. It's loaded
# at runtime from /etc/xdg/obs-scenes/brands/<name>.json, which is
# nix-config's (private) concern to provision, not gisnix's: gisnix is the
# mechanism, a specific company's actual brand tokens, tagline and logo
# path are that company's data, supplied from outside. See
# load_brand_overrides() below for the exact JSON shape expected.
#
# The "slant panel" look (build_card_scene) is built from plain rotated
# colour rectangles, not from any brand pack's pre-rendered artwork — the
# same diagonal-panel *device* a brand pack like Kartoza's might ship as a
# bitmap, recreated geometrically instead, which is why it works for any
# brand's colours, public or private, without needing that artwork here.
# --------------------------------------------------------------------------
BRANDS = {
    "qgis": {
        "collection": "QGIS",
        "panel": "#062436",  # sampled from resources/qgis-spatial-splash.png
        "primary": "#4D6E2F",
        "secondary": "#62882E",
        "cloud": "#F5F5F2",
        "white": "#FFFFFF",
        "logo": None,
        "wordmark": "QGIS",
        "tagline": "A Free and Open Source Geographic Information System",
    },
}

BRAND_OVERRIDE_DIR = "/etc/xdg/obs-scenes/brands"


def load_brand_overrides():
    """Each /etc/xdg/obs-scenes/brands/<name>.json becomes BRANDS[<name>],
    replacing a built-in entry of the same name outright if one exists
    (private data should always win over a public default, not merge
    field-by-field with it). Required keys: collection, panel, primary,
    secondary, cloud, white, logo (a file path or null), wordmark (a
    string shown instead of an image, or null), tagline. Optional: motif —
    a file path to a full-canvas-aspect-ratio PNG with the brand's own
    diagonal-panel artwork already composited in (see build_card_scene),
    used in place of the geometric slant panel when present; omit or set
    null to keep the geometric look. A malformed file is skipped with a
    warning, not a crash — one bad brand file shouldn't take every brand
    down with it."""
    if not os.path.isdir(BRAND_OVERRIDE_DIR):
        return
    for path in sorted(glob.glob(os.path.join(BRAND_OVERRIDE_DIR, "*.json"))):
        name = os.path.splitext(os.path.basename(path))[0]
        try:
            with open(path) as f:
                BRANDS[name] = json.load(f)
        except (OSError, json.JSONDecodeError) as exc:
            print(f"Warning: couldn't load brand '{name}' from {path}: {exc}", file=sys.stderr)

# Intro first, then every working/content scene, then Outro, then BRB —
# also the order obs-scene-step cycles through (j/k) and the order
# build_all() creates them in, so OBS's own scene list reads the same
# way top to bottom. kanata-keyboard.nix's obs-scene-step script carries
# an identical copy of this list (bash can't import Python) — change one,
# change the other, or j/k and this stop agreeing on what's next.
SCENE_BASE_NAMES = ["Intro", "Webcam", "Screen", "ScreenCam", "ScreenOverlay", "Terminal", "Outro", "BRB"]

CANVAS_W, CANVAS_H = 1920, 1080
BORDER = 24  # branded frame thickness, Screen/ScreenCam/ScreenOverlay/Terminal
# color_filter_v2's own opacity range is 0-1, NOT the legacy color_filter's
# 0-100 — confirmed against real-world reports of the two behaving
# differently (obsproject/obs-studio#4989), not assumed. 0.7 is readable
# text over a readable face, the "VU-meter overlay" look — tune to taste.
TERMINAL_OPACITY = 0.7

# text_ft2_source_v2 face names — Lato ships via nixpkgs (pkgs.lato, wired
# into fonts.packages by obs-scenes.nix) so fontconfig resolves these by
# family name; no font file path needed in the source settings.
FONT_BLACK = "Lato Black"
FONT_BOLD = "Lato Bold"
FONT_REGULAR = "Lato"

# OBS source kinds — the one thing here most likely to need adjusting on a
# given OBS build (plugin set, Wayland vs X11). First CreateInput failure
# prints `GetInputKindList`'s own output, which is the actual source of
# truth for what's available.
KIND_COLOR = "color_source_v3"
KIND_IMAGE = "image_source"
KIND_TEXT = "text_ft2_source_v2"
KIND_WEBCAM = "v4l2_input"
KIND_SCREEN = "pipewire-screen-capture-source"  # portal-based — cosmic-comp has no wlr-screencopy
KIND_OVERLAY = "input-overlay"

# Default keyboard overlay (obs-scenes.nix deploys these two unconditionally
# — see that file's own comment for the license/source) so ScreenOverlay
# isn't a blank box the first time anyone opens it. 360px wide keeps a
# full keyboard readable without swallowing the corner of a 1920x1080
# capture; height follows from the texture's own aspect ratio (see
# SceneBuilder.overlay).
DEFAULT_OVERLAY_TEXTURE = "/etc/xdg/obs-scenes/input-overlay-texture.png"
DEFAULT_OVERLAY_LAYOUT = "/etc/xdg/obs-scenes/input-overlay-layout.json"
DEFAULT_OVERLAY_WIDTH = 360


def png_dimensions(path):
    """(width, height) read straight from the PNG IHDR chunk — stdlib only,
    no Pillow dependency just to size one background image before scaling
    it to canvas. Returns None for anything that isn't a well-formed PNG;
    callers treat that as "place unscaled" rather than crashing on it."""
    try:
        with open(path, "rb") as f:
            header = f.read(24)
    except OSError:
        return None
    if header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        return None
    return int.from_bytes(header[16:20], "big"), int.from_bytes(header[20:24], "big")


def abgr(hex_color, alpha=255):
    """OBS color_source packs its `color` setting as 0xAABBGGRR, not ARGB —
    confirmed against OBS's own color_source.c. If a colour renders swapped
    on screen, this is the first thing to re-check."""
    h = hex_color.lstrip("#")
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return (alpha << 24) | (b << 16) | (g << 8) | r


def scene_name(b, base):
    # Namespaced per brand ("Kartoza Webcam", "QGIS Webcam") so the two
    # brands' scenes read unambiguously in OBS's own scene list and in
    # obs-cli output, even though each brand already lives in its own
    # scene COLLECTION (a separate OBS namespace on its own) — this is
    # about readability, not avoiding a real collision.
    return f"{b['collection']} {base}"


def pick_webcam():
    """First /dev/video* that isn't obs.nix's v4l2loopback sink
    (video_nr=1, i.e. /dev/video1) — that device is OBS's own virtual-
    camera OUTPUT, not something to read a scene's webcam source from."""
    for dev in sorted(glob.glob("/dev/video*")):
        if dev != "/dev/video1":
            return dev
    return "/dev/video0"


IDENTITY_CACHE = os.path.expanduser("~/.config/gisnix/obs-identity.json")


def gum_prompt(label, placeholder):
    """Best-effort interactive prompt — falls back to the placeholder
    outright (never crashes the build) if gum isn't on PATH, stdin isn't a
    terminal, or the user just hits enter on an empty answer."""
    try:
        result = subprocess.run(
            ["gum", "input", "--prompt", f"{label}: ", "--placeholder", placeholder],
            capture_output=True,
            text=True,
            timeout=120,
        )
        value = result.stdout.strip()
        return value if value else placeholder
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        return placeholder


def get_identity():
    """Name and email first from this host's own Nix config (obs-
    scenes.nix writes one identity-<user>.json per real user, sourced from
    users.users.<name>.description and kartoza.userEmails — the same
    per-user email declaration kanata's own email macro already uses, see
    kanata-email.nix) — authoritative when present, since it's centrally
    declared rather than typed into a prompt each time. Role has no Nix
    source at all, so it's always asked. Anything gum has to ask for gets
    cached in IDENTITY_CACHE so it's only asked once, not on every run.
    """
    cache = {}
    if os.path.exists(IDENTITY_CACHE):
        with open(IDENTITY_CACHE) as f:
            try:
                cache = json.load(f)
            except json.JSONDecodeError:
                cache = {}

    nix_identity = {}
    username = pwd.getpwuid(os.getuid()).pw_name
    nix_identity_path = f"/etc/xdg/obs-scenes/identity-{username}.json"
    if os.path.exists(nix_identity_path):
        with open(nix_identity_path) as f:
            try:
                nix_identity = json.load(f)
            except json.JSONDecodeError:
                nix_identity = {}

    identity = {
        "name": nix_identity.get("name") or cache.get("name") or gum_prompt("Your name", "Your Name"),
        "email": nix_identity.get("email") or cache.get("email") or gum_prompt("Your email", "you@example.com"),
        "role": cache.get("role") or gum_prompt("Your role/title", "GIS Analyst"),
    }

    if identity != cache:
        os.makedirs(os.path.dirname(IDENTITY_CACHE), exist_ok=True)
        with open(IDENTITY_CACHE, "w") as f:
            json.dump(identity, f, indent=2)

    return identity


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


RESOURCE_ALREADY_EXISTS = 601  # obs-websocket RequestStatus — stable protocol constants, not ours to pick
INVALID_INPUT_KIND = 605


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
        # previous run, which CreateScene refuses outright. main()'s
        # upfront sweep is meant to have already cleared this, but that
        # sweep is a best-effort snapshot-then-act pass — catching the
        # specific "already exists" code here and removing+retrying right
        # at the point of failure doesn't depend on that snapshot having
        # been perfectly complete or race-free. Safe to remove ONLY
        # because main() guarantees a scratch scene exists before any of
        # this runs — OBS refuses to remove a collection's LAST scene,
        # and this one might well be it.
        try:
            client.create_scene(scene_name)
        except OBSSDKRequestError as exc:
            if exc.code != RESOURCE_ALREADY_EXISTS:
                raise
            client.remove_scene(scene_name)
            client.create_scene(scene_name)

    def _place(self, item_id, x, y, w=None, h=None, source_w=None, source_h=None, rotation=None):
        t = {"positionX": float(x), "positionY": float(y)}
        if w is not None and source_w:
            t["scaleX"] = w / source_w
        if h is not None and source_h:
            t["scaleY"] = h / source_h
        if rotation is not None:
            t["rotation"] = float(rotation)
        self.cl.set_scene_item_transform(self.scene, item_id, t)

    def _create_input(self, name, kind, settings):
        # Same self-healing shape as SceneBuilder.__init__ above, for the
        # same reason: main()'s upfront sweep of "<scene> <thing>"-prefixed
        # inputs is best-effort, not a guarantee — this is what actually
        # makes a retry safe regardless of why a name was still taken.
        full_name = f"{self.scene} {name}"
        try:
            return self.cl.create_input(self.scene, full_name, kind, settings, True)
        except OBSSDKRequestError as exc:
            if exc.code != RESOURCE_ALREADY_EXISTS:
                raise
            self.cl.remove_input(full_name)
            return self.cl.create_input(self.scene, full_name, kind, settings, True)

    def color(self, name, hex_color, x, y, w, h, alpha=255, rotation=None):
        resp = self._create_input(name, KIND_COLOR, {"color": abgr(hex_color, alpha), "width": w, "height": h})
        self._place(resp.scene_item_id, x, y, rotation=rotation)
        return resp.scene_item_id

    def image(self, name, path, x, y, w=None, h=None, source_w=None, source_h=None):
        resp = self._create_input(name, KIND_IMAGE, {"file": path})
        self._place(resp.scene_item_id, x, y, w, h, source_w, source_h)
        return resp.scene_item_id

    def text(self, name, text_value, color_hex, x, y, size=64, face=FONT_REGULAR):
        settings = {
            "text": text_value,
            "color1": abgr(color_hex),
            "color2": abgr(color_hex),
            "font": {"face": face, "size": size},
        }
        resp = self._create_input(name, KIND_TEXT, settings)
        self._place(resp.scene_item_id, x, y)
        return resp.scene_item_id

    def overlay(self, name, x, y, w=None, texture=None, layout=None):
        # The actual obs_data settings keys (confirmed from the plugin's
        # own compiled strings — its UI labels, "Overlay.Path.Texture" /
        # "Overlay.Path.Layout", are NOT the settings keys): io.overlay_image
        # for the texture PNG, io.layout_file for the layout JSON. Without
        # both, the source has nothing to draw and OBS shows an empty box —
        # obs-scenes.nix deploys a default pair (resources/input-overlay,
        # vendored from the input-overlay project's own presets) so this
        # isn't blank out of the box; a host is still free to point this at
        # its own texture/layout by hand in OBS's Properties dialog later.
        settings = {}
        if texture and os.path.exists(texture):
            settings["io.overlay_image"] = texture
        if layout and os.path.exists(layout):
            settings["io.layout_file"] = layout
        resp = self._create_input(name, KIND_OVERLAY, settings)
        h = source_w = source_h = None
        if w is not None and texture:
            dims = png_dimensions(texture)
            if dims:
                source_w, source_h = dims
                h = w * source_h / source_w  # uniform scale — both axes need a target or OBS only stretches X
        self._place(resp.scene_item_id, x, y, w=w, h=h, source_w=source_w, source_h=source_h)
        return resp.scene_item_id

    def capture(self, name, x, y, w, h):
        # An UNSHARED screen/window capture — for a one-off per-scene
        # capture like the Terminal scene's own terminal window, as
        # opposed to the cross-scene Screen Capture source (see
        # ensure_screen_capture) every Screen/ScreenCam/ScreenOverlay
        # scene links in instead. No settings pre-filled: the portal
        # prompts you to pick a screen or window the first time this
        # input actually runs. Returns the full (scene-prefixed) source
        # name, not a scene-item id, since callers that need to attach a
        # filter (CreateSourceFilter) address the SOURCE by name.
        resp = self._create_input(name, KIND_SCREEN, {})
        self._place(resp.scene_item_id, x, y, w, h, source_w=CANVAS_W, source_h=CANVAS_H)
        return f"{self.scene} {name}"

    def link(self, source_name, x, y, w=None, h=None, source_w=None, source_h=None):
        # Attaches an EXISTING, scene-independent source (see
        # ensure_shared_input) into THIS scene via CreateSceneItem,
        # instead of _create_input making a fresh, independent copy of
        # it. The point: Intro/BRB/Outro's logo and tagline are the same
        # literal source object rather than three near-identical copies
        # that could quietly drift apart from each other — the position
        # passed here still has to be repeated per call (CreateSceneItem
        # gives every scene its OWN item id/transform even when the
        # underlying source is shared), but the pixel CONTENT (image data
        # or text) can never go out of sync between scenes this way.
        resp = self.cl.create_scene_item(self.scene, source_name, True)
        self._place(resp.scene_item_id, x, y, w=w, h=h, source_w=source_w, source_h=source_h)
        return resp.scene_item_id

    def slant_panel(self, name, hex_color, angle_deg=8):
        # The brand pack's signature device (brand/.../motif/slant_*.png in
        # the private asset pack): a solid panel with one diagonal edge,
        # covering roughly the left 40% of frame. Recreated geometrically
        # (an oversized rectangle, rotated around its top-left corner —
        # OBS's default scene-item pivot) rather than from that artwork, so
        # it needs no image asset and works for any brand colour.
        #
        # Oversized on purpose: 1000 wide, 2000 tall (canvas is only 1080
        # tall) positioned well above the canvas top, so the rotated
        # rectangle's edges run off both the top and bottom of frame no
        # matter the small rotation below — no visible gap at either edge,
        # even if the angle needs adjusting later. The right edge of that
        # rectangle becomes the panel's diagonal — a bigger angle swings it
        # further across the frame from top to bottom.
        w, h = 1000, 2000
        x, y = 0, -460
        return self.color(name, hex_color, x, y, w, h, rotation=angle_deg)


# Card scene vertical rhythm — one set of numbers shared by every call to
# build_card_scene, rather than per-call magic numbers that could drift
# between Intro/BRB/Outro. Each element's Y is the previous one's bottom
# edge plus CARD_GAP, computed from its actual rendered height (not
# guessed) — a gap big enough to read as deliberate whitespace, not a
# margin of error. Subtext's absence (BRB has none) doesn't move anything
# else, since headline/tagline don't depend on whether it rendered.
CARD_LOGO_X = 140
CARD_LOGO_Y = 120
CARD_LOGO_SIZE = 120  # target rendered height in px — see brand_mark's own note on why this didn't used to mean anything
CARD_GAP = 48
CARD_HEADLINE_SIZE = 104
CARD_HEADLINE_LINE_HEIGHT = 1.25  # text_ft2_source_v2 has no exposed line-metrics API — Lato Black's cap-to-descender span approximated from its own font metrics, not measured pixel-for-pixel (see this file's own top-of-file disclaimer)
CARD_SUBTEXT_SIZE = 36
CARD_TAGLINE_SIZE = 22


def ensure_shared_input(cl, name, kind, settings):
    """Create (or replace) a source that isn't owned by any one scene —
    obs-websocket has no true scene-less CreateInput, so this attaches it
    to SCRATCH_SCENE purely as a landing spot; the source persists once
    created regardless of what happens to that scene afterwards
    (RemoveScene only drops THAT scene's own reference to a source, never
    the source itself — confirmed against every other scene here, which
    already survive the scratch-scene teardown at the end of a build).
    Self-heals the same way SceneBuilder._create_input does, so a retry
    or a deliberate --force rebuild replaces it cleanly rather than
    erroring on "already exists". Returns `name` itself — callers want
    the source NAME to pass to CreateSceneItem later, not the scratch
    scene's own (irrelevant, about to be torn down) scene-item id."""
    try:
        cl.create_input(SCRATCH_SCENE, name, kind, settings, True)
    except OBSSDKRequestError as exc:
        if exc.code != RESOURCE_ALREADY_EXISTS:
            raise
        cl.remove_input(name)
        cl.create_input(SCRATCH_SCENE, name, kind, settings, True)
    return name


def ensure_card_brand_mark(cl, b):
    """The card scenes' shared logo/wordmark — see ensure_shared_input.
    Card-scene-sized (size=120) specifically; Webcam/Screen keep their
    own independently-placed, differently-sized marks (genuinely
    different layouts, corner marks rather than a title-card headline),
    so sharing across those would need per-scene transforms anyway and
    gains nothing — this is scoped to the Intro/BRB/Outro trio, where
    the brand pack's own packs show it as literally the same mark."""
    name = f"{b['collection']} Card Brand Mark"
    if b["logo"] and os.path.exists(b["logo"]):
        return ensure_shared_input(cl, name, KIND_IMAGE, {"file": b["logo"]})
    settings = {
        "text": b["wordmark"] or b["collection"],
        "color1": abgr(b["white"]),
        "color2": abgr(b["white"]),
        "font": {"face": FONT_BLACK, "size": CARD_LOGO_SIZE},
    }
    return ensure_shared_input(cl, name, KIND_TEXT, settings)


def ensure_card_tagline(cl, b):
    """The card scenes' shared strapline — see ensure_shared_input."""
    name = f"{b['collection']} Card Tagline"
    settings = {
        "text": b["tagline"],
        "color1": abgr(b["secondary"]),
        "color2": abgr(b["secondary"]),
        "font": {"face": FONT_REGULAR, "size": CARD_TAGLINE_SIZE},
    }
    return ensure_shared_input(cl, name, KIND_TEXT, settings)


def ensure_camera(cl, b, webcam_device):
    """One webcam source, linked into both Webcam (full-canvas) and
    ScreenCam (small PiP) — see ensure_shared_input. Beyond staying in
    sync if the device ever changes, this avoids two independent v4l2
    opens of the same physical camera at once, which not every driver
    handles cleanly."""
    name = f"{b['collection']} Camera"
    return ensure_shared_input(cl, name, KIND_WEBCAM, {"device_id": webcam_device})


def ensure_screen_capture(cl, b):
    """One screen-capture source, linked into Screen/ScreenCam/
    ScreenOverlay — see ensure_shared_input. Also means the xdg-desktop-
    portal screen/window picker only has to be granted ONCE: each
    independent pipewire-screen-capture-source instance prompts fresh on
    its own first use, so three separate sources meant three separate
    portal prompts for what was always meant to be the same capture."""
    name = f"{b['collection']} Screen Capture"
    return ensure_shared_input(cl, name, KIND_SCREEN, {})


def brand_mark(b, s, x, y, size=96, face=FONT_BLACK):
    """Logo image if the brand has one, else a styled wordmark. `size` is
    the target rendered HEIGHT in pixels either way — the image branch
    used to place the logo file at its own native resolution with no
    scaling at all, which for Kartoza's actual 512x512 logo.png meant a
    512px-tall mark wherever this was called, `size` silently ignored.
    Used by Webcam/Screen's own per-scene marks — card scenes use the
    shared ensure_card_brand_mark + SceneBuilder.link instead, see
    above."""
    if b["logo"] and os.path.exists(b["logo"]):
        dims = png_dimensions(b["logo"])
        if dims:
            source_w, source_h = dims
            w = size * source_w / source_h  # uniform scale to a `size`-tall mark — see image()'s own note on why both axes need a target
            s.image("Brand Logo", b["logo"], x, y, w=w, h=size, source_w=source_w, source_h=source_h)
        else:
            s.image("Brand Logo", b["logo"], x, y)
    else:
        s.text("Brand Wordmark", b["wordmark"] or b["collection"], b["white"], x, y, size=size, face=face)


def build_webcam_scene(cl, b, camera, identity):
    s = SceneBuilder(cl, scene_name(b, "Webcam"))
    s.color("Background", b["cloud"], 0, 0, CANVAS_W, CANVAS_H)
    s.link(camera, 0, 0, w=CANVAS_W, h=CANVAS_H, source_w=CANVAS_W, source_h=CANVAS_H)
    # Lower-third: panel + accent rule + name, the classic talking-head
    # treatment — solid charcoal panel (brand pack's own "no gradients"
    # rule), one thin accent-colour rule above it, name in big bold Lato.
    s.color("Lower Third Rule", b["primary"], 0, 846, 640, 8)
    s.color("Lower Third Panel", b["panel"], 0, 854, 640, 130, alpha=235)
    s.text("Lower Third Name", identity["name"], b["white"], 32, 866, size=56, face=FONT_BLACK)
    s.text("Lower Third Role", identity["role"], b["primary"], 32, 932, size=26, face=FONT_REGULAR)
    brand_mark(b, s, CANVAS_W - 220, 32, size=56)


def build_screen_scene(cl, b, screen_capture, name="Screen"):
    s = SceneBuilder(cl, scene_name(b, name))
    s.color("Background", b["panel"], 0, 0, CANVAS_W, CANVAS_H)
    s.link(
        screen_capture,
        BORDER,
        BORDER,
        w=CANVAS_W - 2 * BORDER,
        h=CANVAS_H - 2 * BORDER,
        source_w=CANVAS_W,
        source_h=CANVAS_H,
    )
    # A thin brand-colour corner flag rather than a full frame — reads as
    # "branded" without competing with whatever's on screen underneath.
    s.color("Corner Flag", b["primary"], CANVAS_W - 180, 0, 180, 10)
    brand_mark(b, s, CANVAS_W - 220, CANVAS_H - 80, size=40)
    return s


def build_screencam_scene(cl, b, screen_capture, camera):
    s = build_screen_scene(cl, b, screen_capture, "ScreenCam")
    pip_w, pip_h = 420, 236
    x, y = CANVAS_W - pip_w - 48, CANVAS_H - pip_h - 48
    s.color("Cam Border", b["secondary"], x - 8, y - 8, pip_w + 16, pip_h + 16)
    s.link(camera, x, y, w=pip_w, h=pip_h, source_w=CANVAS_W, source_h=CANVAS_H)


def build_screenoverlay_scene(cl, b, screen_capture):
    s = build_screen_scene(cl, b, screen_capture, "ScreenOverlay")
    texture = DEFAULT_OVERLAY_TEXTURE if os.path.exists(DEFAULT_OVERLAY_TEXTURE) else None
    layout = DEFAULT_OVERLAY_LAYOUT if os.path.exists(DEFAULT_OVERLAY_LAYOUT) else None
    dims = png_dimensions(texture) if texture else None
    h = DEFAULT_OVERLAY_WIDTH * dims[1] / dims[0] if dims else 220
    s.overlay(
        "Input Overlay",
        48,
        CANVAS_H - 48 - h,
        w=DEFAULT_OVERLAY_WIDTH,
        texture=texture,
        layout=layout,
    )


def build_terminal_scene(cl, b, camera):
    # Talk to camera with a terminal visible at the same time — the
    # full-canvas camera is the base layer, a full-canvas terminal/window
    # capture sits on top at TERMINAL_OPACITY, the "VU-meter overlay"
    # look streamers use: neither fully hides the other, both read at
    # once. The capture itself has no settings pre-filled — same one-time
    # portal setup as any other screen/window capture here, pick the
    # terminal window the first time this scene is used.
    s = SceneBuilder(cl, scene_name(b, "Terminal"))
    s.color("Background", b["panel"], 0, 0, CANVAS_W, CANVAS_H)
    s.link(camera, 0, 0, w=CANVAS_W, h=CANVAS_H, source_w=CANVAS_W, source_h=CANVAS_H)
    terminal_source = s.capture("Window Capture", 0, 0, CANVAS_W, CANVAS_H)
    cl.create_source_filter(terminal_source, "Transparency", "color_filter_v2", {"opacity": TERMINAL_OPACITY})
    brand_mark(b, s, CANVAS_W - 220, CANVAS_H - 80, size=40)


def build_card_scene(cl, b, base_name, headline, sub, card_logo, card_tagline):
    # Big, strong, bold — this is a title card, not a caption: a headline
    # this size is the whole point of the scene, not competing with
    # anything else on screen the way the lower-third text does.
    s = SceneBuilder(cl, scene_name(b, base_name))
    # "motif" is optional brand data (see load_brand_overrides): a full
    # CANVAS-aspect-ratio background with the brand's real diagonal-panel
    # artwork already composited in (the brand pack's own slant_title.png,
    # for Kartoza) — the right-hand art slant_panel's geometric rectangle
    # can't recreate, since that rectangle is deliberately plain colour so
    # it works for any brand without needing artwork at all. A brand with
    # no motif (QGIS) falls back to the flat-colour + geometric-panel look
    # exactly as before.
    motif = b.get("motif")
    motif_dims = png_dimensions(motif) if motif and os.path.exists(motif) else None
    if motif_dims:
        mw, mh = motif_dims
        s.image("Background", motif, 0, 0, w=CANVAS_W, h=CANVAS_H, source_w=mw, source_h=mh)
    else:
        s.color("Background", b["cloud"], 0, 0, CANVAS_W, CANVAS_H)
        s.slant_panel("Slant Panel", b["panel"])

    # Logo and tagline are shared sources (see ensure_card_brand_mark /
    # ensure_card_tagline) linked in here, not independently recreated —
    # the same literal object in Intro/BRB/Outro, placed at the same x/y
    # every time, rather than three copies that could quietly diverge.
    logo_dims = png_dimensions(b["logo"]) if b["logo"] and os.path.exists(b["logo"]) else None
    logo_w = CARD_LOGO_SIZE * logo_dims[0] / logo_dims[1] if logo_dims else CARD_LOGO_SIZE
    s.link(
        card_logo,
        CARD_LOGO_X,
        CARD_LOGO_Y,
        w=logo_w,
        h=CARD_LOGO_SIZE,
        source_w=logo_dims[0] if logo_dims else None,
        source_h=logo_dims[1] if logo_dims else None,
    )
    logo_bottom = CARD_LOGO_Y + CARD_LOGO_SIZE

    headline_y = logo_bottom + CARD_GAP
    s.text("Headline", headline, b["white"], 136, headline_y, size=CARD_HEADLINE_SIZE, face=FONT_BLACK)
    headline_bottom = headline_y + CARD_HEADLINE_SIZE * CARD_HEADLINE_LINE_HEIGHT

    if sub:
        subtext_y = headline_bottom + CARD_GAP
        s.text("Subtext", sub, b["primary"], 140, subtext_y, size=CARD_SUBTEXT_SIZE, face=FONT_BOLD)

    # Tagline sits near the bottom of frame regardless — already well
    # clear of the headline/subtext block above under any brand's text,
    # so it doesn't need to follow the same cascading math.
    s.link(card_tagline, 140, CANVAS_H - 90)


# Never a real scene name — exists only so OBS always has a scene to fall
# back to while every real one gets torn down and rebuilt. OBS refuses to
# leave a collection with zero scenes, so without this, rebuilding
# whichever scene happens to be the last one left would fail outright.
SCRATCH_SCENE = "_gisnix_scratch_"


def build_all(cl, b, webcam_device, identity):
    # Created once, linked into every scene that needs them — see
    # ensure_camera / ensure_screen_capture / SceneBuilder.link. Besides
    # keeping them in sync, this means the portal screen/window picker
    # only has to be granted once (per ensure_screen_capture's own note),
    # and avoids two v4l2 opens of the same physical camera at once.
    camera = ensure_camera(cl, b, webcam_device)
    screen_capture = ensure_screen_capture(cl, b)

    # Created once, linked into all three card scenes — see
    # ensure_card_brand_mark / ensure_card_tagline / SceneBuilder.link.
    card_logo = ensure_card_brand_mark(cl, b)
    card_tagline = ensure_card_tagline(cl, b)

    # Build order matches SCENE_BASE_NAMES exactly — see that constant's
    # own comment for why: OBS's own scene list then reads the same way
    # top to bottom, and it's the order j/k (obs-scene-step) cycles
    # through. Intro first, every working/content scene, then Outro,
    # then BRB.
    build_card_scene(cl, b, "Intro", "Starting soon", identity["email"], card_logo, card_tagline)
    build_webcam_scene(cl, b, camera, identity)
    build_screen_scene(cl, b, screen_capture)
    build_screencam_scene(cl, b, screen_capture, camera)
    build_screenoverlay_scene(cl, b, screen_capture)
    build_terminal_scene(cl, b, camera)
    build_card_scene(cl, b, "Outro", "Goodbye!", identity["email"], card_logo, card_tagline)
    build_card_scene(cl, b, "BRB", "Be right back", None, card_logo, card_tagline)


# Preference order, not a hard requirement — set_transition() below asks
# OBS what it actually has (GetSceneTransitionList) and walks this list
# looking for the first match, rather than assuming any one of these
# exists by this exact name on every OBS version/build.
#
# "Move" (obs-move-transition, installed by obs.nix) is the fancier pick
# and listed first, but there is no obs-websocket request to CREATE a new
# transition instance — only to select among ones that already exist.
# OBS auto-creates instances of its OWN built-ins (Fade/Slide/Swipe/Luma
# Wipe/Cut) in every fresh scene collection; it does NOT auto-create one
# for a plugin-provided kind like move_transition. So "Move" only starts
# winning this preference once you've added one yourself, once, via the
# "+" in OBS's own Scene Transitions dock — after that this script picks
# it up automatically on every future run, same as the built-ins.
TRANSITION_PREFERENCE = ["Move", "Slide", "Swipe", "Luma Wipe", "Fade"]
TRANSITION_DURATION_MS = 450


def set_transition(cl):
    # "Gorgeous animated transitions from one scene to another" — OBS has
    # no per-scene-pair transition API via obs-websocket; SetCurrentScene-
    # Transition sets ONE active transition used for every SetCurrent-
    # ProgramScene switch collection-wide (Cut is the other common
    # default, and deliberately not in TRANSITION_PREFERENCE — it's instant,
    # the opposite of what was asked for). obs-transition-table (also
    # installed) can do an actual different transition per scene-pair, but
    # that's configured entirely in its own OBS dock UI — nothing in the
    # websocket protocol exposes it to set up remotely.
    available = {t["transitionName"] for t in cl.get_scene_transition_list().transitions}
    for name in TRANSITION_PREFERENCE:
        if name in available:
            cl.set_current_scene_transition(name)
            cl.set_current_scene_transition_duration(TRANSITION_DURATION_MS)
            return name
    return None  # none of the preferred ones exist — leave OBS's own default alone


def main():
    load_brand_overrides()  # before argparse: --help/choices must reflect what's actually installed

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("brand", choices=sorted(BRANDS))
    parser.add_argument("--force", action="store_true", help="tear down and rebuild if the collection exists")
    parser.add_argument("--host", default="localhost")
    parser.add_argument("--port", type=int, default=4455)
    parser.add_argument("--password", default="")
    args = parser.parse_args()

    b = BRANDS[args.brand]
    scenes = [scene_name(b, base) for base in SCENE_BASE_NAMES]

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

    try:
        existing_scenes = {s["sceneName"] for s in cl.get_scene_list().scenes}
        if SCRATCH_SCENE not in existing_scenes:
            cl.create_scene(SCRATCH_SCENE)

        # Orphaned sources from an earlier interrupted run: RemoveScene
        # drops the scene but NOT the inputs that were in it (they just
        # stop appearing in any scene) — so a retry's CreateInput would
        # still hit "A source already exists by that input name" even
        # after SceneBuilder recreates the scene itself clean. Every
        # input this script ever creates is named "<scene> <thing>", so
        # sweeping by that prefix catches them regardless of which scene
        # they came from or whether that scene still exists.
        existing_inputs = [i["inputName"] for i in cl.get_input_list().inputs]
        prefixes = tuple(f"{scene} " for scene in scenes)
        for input_name in existing_inputs:
            if input_name.startswith(prefixes):
                cl.remove_input(input_name)

        webcam_device = pick_webcam()
        print(f"Webcam device: {webcam_device}")
        identity = get_identity()
        print(f"Identity: {identity['name']} <{identity['email']}>, {identity['role']}")
        print(
            "Note: the first time a Screen Capture source actually runs, the "
            "desktop portal will pop up a share picker — pick a display/window "
            "and confirm, or the screen scenes stay blank. That's a one-time, "
            "OS-level permission prompt; nothing here can pre-approve it."
        )
        build_all(cl, b, webcam_device, identity)

        for scene in cl.get_scene_list().scenes:
            if scene["sceneName"] not in scenes:
                cl.remove_scene(scene["sceneName"])

        transition = set_transition(cl)

        cl.set_current_program_scene(scene_name(b, "Screen"))
    except OBSSDKRequestError as exc:
        # No traceback — req_name/code/comment (folded into str(exc) by
        # obsws-python itself) are already the useful part; a stack
        # through seven build_*_scene calls adds noise, not information.
        print(f"OBS rejected a request while building the collection: {exc}", file=sys.stderr)
        print(file=sys.stderr)
        if exc.code == INVALID_INPUT_KIND:
            # The one failure mode worth more than generic advice: ask OBS
            # itself what it actually has, right now, on this machine —
            # beats guessing kind-name spellings blind from outside it.
            print("OBS doesn't recognise one of the source kinds this script asked for.", file=sys.stderr)
            try:
                available = sorted(cl.get_input_kind_list(unversioned=True).input_kinds)
                print("Kinds this OBS actually has available:", file=sys.stderr)
                for kind in available:
                    print(f"  - {kind}", file=sys.stderr)
                for wanted, used_for in (
                    (KIND_WEBCAM, "the webcam"),
                    (KIND_SCREEN, "screen capture"),
                    (KIND_OVERLAY, "the keystroke/mouse overlay"),
                ):
                    if wanted not in available:
                        print(f'  -> "{wanted}" ({used_for}) is missing — that plugin isn\'t loaded.', file=sys.stderr)
            except Exception:  # noqa: BLE001 — best-effort extra diagnostic; don't let it hide the real error
                pass
            print(file=sys.stderr)
        print("What to try:", file=sys.stderr)
        print("  - Re-run with --force. This script cleans up whatever the failed", file=sys.stderr)
        print("    attempt left behind (scratch scene, orphaned sources) before", file=sys.stderr)
        print("    rebuilding, so a retry is always safe.", file=sys.stderr)
        print("  - If it fails at the same request every time, the message above", file=sys.stderr)
        print("    names the scene/source OBS rejected — check its Sources panel", file=sys.stderr)
        print("    for it directly, and whether a plugin this needs (input-overlay,", file=sys.stderr)
        print("    v4l2loopback) is actually installed and enabled.", file=sys.stderr)
        sys.exit(1)
    except Exception as exc:  # noqa: BLE001 — catch-all: still no raw traceback, still a next step
        print(f"obs-setup failed partway through: {exc}", file=sys.stderr)
        print("Re-run with --force — this script cleans up after a failed attempt", file=sys.stderr)
        print("before rebuilding. If it keeps failing the same way, that's the exact", file=sys.stderr)
        print("message to go looking for (or report).", file=sys.stderr)
        sys.exit(1)
    print(f"'{b['collection']}' built: {', '.join(scenes)}")
    if transition:
        print(f"Scene transition: {transition} ({TRANSITION_DURATION_MS}ms)")
    else:
        print("No preferred transition (Slide/Swipe/Luma Wipe/Fade) found — left OBS's own default alone.")


if __name__ == "__main__":
    main()
