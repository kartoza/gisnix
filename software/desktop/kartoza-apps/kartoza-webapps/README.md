# kartoza-webapps

Site-specific browser apps — GMail, ERPNext, the training portal, WhatsApp Web —
packaged so they behave like native desktop apps: own launcher entry, own icon in
the panel, own browser profile.

Each app becomes two things: a `writeShellScriptBin` launcher that opens Chromium
in `--app=` mode, and a `.desktop` entry with a matching icon.

## Adding a webapp

1. **Drop the icon in `assets/`.** SVG preferred, PNG accepted. Name it after the
   app id you are about to use, e.g. `assets/kartoza-foo.svg`.

2. **Add a five-line entry to `apps` in `default.nix`:**

   ```nix
   kartoza-foo = {
     name = "Kartoza Foo";                  # shown in the launcher
     url = "https://foo.kartoza.com";
     categories = [ "Network" "Office" ];   # XDG menu categories
     icon = "kartoza-foo.svg";              # filename in assets/
   };
   ```

3. **Enable it.** `programs.kartoza-webapps.enableAll = true` (what
   `../kartoza-webapps.nix` sets) picks it up automatically. To be selective,
   set `programs.kartoza-webapps.apps.kartoza-foo.enable = true` instead.

4. **Rebuild, then verify the icon actually attaches to the running window:**

   ```console
   $ lswt | grep foo
   chrome-foo.kartoza.com__-Default   "Foo | Kartoza"
   ```

   The `app-id` column must exactly match the generated `.desktop` filename.
   If the panel shows a generic cog, that match is what broke.

That is the whole process. Everything below is *why* it is shaped this way —
read it before changing the machinery, because each rule here was a bug first.

## Why the desktop file has a strange name

The launcher and the panel answer different questions.

The **launcher** lists `.desktop` files. `Icon=` resolves against the icon theme
and cannot really break.

The **panel** sees a *running window* and has to work backwards to an
application. On Wayland the only clue a window gives is its **`app_id`**, and
the panel looks for a desktop entry whose *filename* matches. No match, no icon.

On X11 this was handled with `StartupWMClass=` matched against `WM_CLASS`, which
browsers let you set with `--class`. Wayland broke that twice:

1. `WM_CLASS` no longer exists; `app_id` replaced it.
2. Chromium **ignores `--class` for `--app=` windows on Wayland** and computes
   the `app_id` itself, as:

   ```text
   chrome-<host>_<path, with "/" replaced by "_">-<profile>
   ```

   So `https://training.kartoza.com` becomes `chrome-training.kartoza.com__-Default`.

`mkWmClass` reproduces that computation in Nix, and the generated desktop file is
*named* after the result. `--class`/`--name` are still passed with the same
string so X11 and XWayland match through the old mechanism too — one desktop
file covers both worlds.

Because each app gets its own `--user-data-dir`, the profile segment is always
`Default`.

## Gotchas

**Never set `NoDisplay=true`.** It is tempting to mark a match-only entry hidden
so it does not clutter the launcher. On COSMIC, hidden entries are skipped during
window matching as well — you get the generic cog back. Entries here must stay
visible.

**`Exec=` names the launcher by absolute store path, not by name.** A launcher
is an ordinary binary in the system profile, and a package installed into a
*user* profile that happens to ship the same name wins — per-user profiles come
first on `PATH`. `protonmail-desktop` in `users/tim.nix` ships `bin/proton-mail`,
the same name as the Proton launcher here, so `Exec=proton-mail` quietly started
the Electron app instead. The symptom is not "wrong application": it is a
**missing icon**, because the Electron window's `app_id` is not the URL-derived
string the desktop file is named after, so the panel has nothing to match.
Pointing `Exec=` at the store path makes the entry immune to whatever else is
on `PATH`. Typing `proton-mail` in a terminal still gets you the desktop app,
which is the right answer for a terminal.

**Icons are namespaced deliberately.** They install as
`kartoza-webapp-<appId>`, not the bare `<appId>`. XDG icon lookup searches the
active theme and its parents *before* hicolor, so Papirus's own `google-meet`,
`google-chat`, `google-drive`, `proton-mail` and `whatsapp` icons silently won
over the curated assets here. The prefix puts them in a namespace no theme ships.

**PNG icons do not go in `scalable/`.** That directory is reserved for vectors,
and some icon loaders honour the spec by refusing to scale a raster found there.
`iconDir` routes PNGs to `64x64/apps` instead. Prefer SVG.

**Changing a URL changes the app_id**, and therefore the desktop filename.
Already-open windows keep the old id — close and reopen them. If the app was
pinned to the panel, re-pin it once, since the pin references the old filename.

## Related

`software/desktop/gis/qgis-wayland-appid.nix` solves the same problem for QGIS,
which reports a truncated `org.qgis.` (with a trailing dot) matching neither
upstream's `org.qgis.qgis.desktop` nor the per-version entries. The fix is the
same medicine: one visible desktop entry named literally `org.qgis..desktop`.

The general recipe for any app showing a generic cog:

1. `lswt` → read the real `app_id`, byte for byte.
2. Make a desktop entry whose filename is exactly `<app_id>.desktop`.
3. Do not set `NoDisplay=true`.
4. Reopen the window.
