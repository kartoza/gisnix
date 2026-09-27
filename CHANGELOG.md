# Changelog

All notable changes to gisnix are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.21.1] - 2026-09-27

### Fixed

- Allow-list the unfree AI assistants (`claude-code`, `antigravity`,
  `google-antigravity-cli`) and Steam (`steam`, `steam-unwrapped`). None were
  named in the allow-list, so a host taking `terminal-ai` or `desktop-games`
  failed to *evaluate* at install ("has an unfree license, refusing to
  evaluate") — the same class as the 0.21.0 Google Earth fix.

### Added

- A CI check (`utils/check-bundle-eval.sh`) that evaluates the example host
  with every non-opt-in bundle enabled, so unfree/insecure/eval failures in a
  bundle the example host doesn't normally build are caught in CI rather than
  on someone's install. Runs on every push (`build-hosts.yml`) and gates
  releases (`release.yml`). It is what surfaced the fixes above.

## [0.21.0] - 2026-09-27

### Added

- A **"The workflow it unlocks"** page in the user guide: how flakes and direnv
  give each project its own toolset that loads on `cd` and unloads when you
  leave, and how changing a machine by description gives you a reviewable diff
  before anything is applied (paired with the sandboxed AI assistants).
- The **Understanding gisnix** page now notes that older QGIS versions can be
  rough (a few need an obsolete WebKit — work is ongoing), that building QGIS
  `master` is a one-line command, and points to the companion `qgis-dev-env`
  project; plus a short mention of screen capture and annotation with satty.
- An **after-install / updating** page in the user guide: where an installed
  machine is described, how to pull gisnix updates when fixes ship upstream
  (`gisnix update --flake`, and how that differs when pinned to a version
  versus tracking main), applying changes, and rolling back via generations.
- **direnv out of the box.** The installer now writes a `.envrc` (`use flake`)
  beside the generated flake, and nix-direnv is wired into every user's direnv
  lib dir, so `cd`-ing into `~/nixos-config` drops you straight into the gisnix
  dev shell (the `gisnix` command and friends) with no manual `nix develop`.
  (First entry needs a one-time `direnv allow`.)
- An **at-a-glance bundle list** on the admin Software bundles page: every
  bundle and its one-line description, generated from the registry, so you can
  see what's available without reading each bundle's full contents.
- A **Supported hardware** page in the user guide: gisnix is well tested on the
  Framework Laptop 16 and 14; on other machines your mileage may vary,
  especially with esoteric hardware or Wi-Fi adapters. It also documents
  **iPhone USB tethering** as a network option during setup — plug in the
  phone, enable Personal Hotspot, and it works out of the box (via `usbmuxd`)
  on both the installer and the installed system. Cross-linked from the
  quickstart's network step.

### Fixed

- `googleearth-pro` (in the `desktop-gis` bundle) is both unfree and marked
  insecure, but was named in neither allow-list — so any host taking that
  bundle failed to *evaluate* ("has an unfree license" / "is marked as
  insecure"), a broken bare-metal install. It's now in both
  `kartoza.unfreePackages` and `kartoza.insecurePackages` beside the package.
- `gisnix update` failed on a normal installed machine with "run from the repo
  root (hosts/fleet.nix missing)". The per-machine flake in `~/nixos-config` is
  a single host with no `hosts/fleet.nix`, so enabling a bundle and rebuilding
  was impossible. `update` now detects the single-host flake and rebuilds this
  machine in place; fleet checkouts are unchanged, and `gisnix update --flake`
  works there too.

## [0.20.0] - 2026-09-27

### Fixed

- The installer's Wi-Fi didn't appear in `nmtui` on MediaTek MT7925 (Wi-Fi 7)
  laptops. The driver, firmware and interface (`wlp192s0`) all came up
  correctly on the 7.2 kernel, and rfkill was clear — but NetworkManager had
  **no wifi backend**: the standalone `wpa_supplicant` is disabled on the ISO
  so it can't fight NM, which left the radio with nothing to drive it, so the
  device sat in state `unavailable`. The installer now sets
  `networking.networkmanager.wifi.backend = "iwd"` — a self-contained backend
  NM manages itself, with strong support for current Wi-Fi 7 chips. Verified
  on bare metal: the device now comes up and `nmtui` can connect.
- Installs failed building the kanata config (`kanata-keyboard-config.kdb`:
  "To use cmd you must put in defcfg: danger-enable-cmd yes"). The default
  kanata config always emits a `cmd` (the herdr record-toggle sound), but
  `danger-enable-cmd yes` was gated on `voxtypePtt || emailScript` — so
  turning `voxtypePtt` off (for the push-to-talk change below) dropped it and
  every install broke at `sudo setup`. It is now unconditional, which is what
  it always needed to be. This slipped through because the pre-release check
  only *evaluated* the config; the `.kdb` is validated at *build* time.
  Guards added so it cannot recur: a `build-hosts` CI workflow builds the
  example host on every push, and `release.yml` builds it as a release gate.
- voxtype push-to-talk now actually works. It is driven by voxtype's **own**
  right-Ctrl hotkey, not by kanata running `voxtype record start/stop`. kanata
  is a system (root) service, and the record client it invoked could neither
  reach the daemon's per-user socket (`/run/user/UID/voxtype`) nor read the
  daemon's config — it read a stale `~/.config` copy and crashed, so the key
  did nothing. voxtype now watches for `RIGHTCTRL` itself via evdev (the user
  is in the `input` group), and kanata passes right Ctrl straight through
  (`voxtypePtt = false`). Verified end to end on real hardware: hold right
  Ctrl, speak, release, transcribed text is typed, with a start/stop beep.

## [0.19.1] - 2026-09-27

### Fixed

- The voxtype daemon crash-looped on the managed config shipped in 0.19.0.
  voxtype 0.7.2 parses its `config.toml` strictly, and the config was missing
  the `[audio]` table whose `device` field has no default — so every start
  failed with `missing field 'device'`. The managed config now carries the
  full `[audio]` table (with `[audio.feedback]` nested under it, where it
  belongs) and mirrors voxtype's own generated defaults for the other required
  fields.

### Changed

- The daemon now reads the gisnix-managed config directly from the Nix store
  (`voxtype --config <store path>`) instead of a copy written into
  `~/.config/voxtype`. The previous write-a-copy step was a `RemainAfterExit`
  oneshot, which does not reliably re-run on `nixos-rebuild switch` — so a
  corrected config could fail to reach the machine on the very rebuild meant
  to deliver it. With the path baked into the service, every rebuild applies
  the current config and there is no on-disk copy to go stale.

## [0.19.0] - 2026-09-26

### Added

- Linux 7.2 is now the default kernel, on both the installer ISO and every
  installed machine, so current hardware works out of the box — the
  MediaTek MT7925 (Wi-Fi 7) radio and AMD Strix Halo graphics/NPU platforms
  need a recent kernel before the installer's `nmtui` can even see the wifi.
  This is only safe because gisnix's nixpkgs now carries ZFS 2.4.4, the
  first OpenZFS release to support the 7.x series; a ZFS root on 7.2 was
  verified to build. The default is `mkDefault` (`profiles/kernel.nix`), so
  a host can still pin a different kernel in its own `hardware.nix`.

### Fixed

- Push-to-talk (voxtype on right-Ctrl hold) is now audible and coherent.
  voxtype's config is written by gisnix (`voxtype-config` user service):
  its own key detection is turned off — it defaulted to Scroll Lock, a key
  many boards, including the Framework 16, don't have — so kanata is the
  single trigger, and its start/stop beep is turned on. The beep now plays
  from voxtype's own user session (where it can reach PipeWire) instead of
  from kanata's system-scope service (where it never could), which is why
  holding right Ctrl felt like nothing was happening even while it was
  recording. The now-redundant kanata-side sound cues were removed.

## [0.18.0] - 2026-09-26

### Added

- A full documentation refresh. The site is rewritten in the voice of
  QGIS's *Gentle Introduction to GIS* — approachable and concept-led — with
  eleven brand-coloured PlantUML diagrams illustrating every key idea
  (architecture, the install journey, first login, bundles, encrypted ZFS,
  generations and rollback, the keyboard and speech pipeline, the AI
  sandbox, locale, downstream fleets). Diagrams render from committed
  `.puml` sources via `gisnix docs-diagrams`.
- The whole install-to-first-command journey is now documented and
  diagrammed: write the ISO, boot, connect the network with `sudo nmtui`,
  run `sudo setup`, reboot into a minimal encrypted-ZFS + COSMIC machine,
  log in, open kitty, `cd ~/nixos-config`, `nix develop`, and reach the
  `gisnix` command compendium. The per-machine flake the installer writes
  now re-exports gisnix's devShells, so that `nix develop` works.
- A single-file PDF of the documentation, built by `gisnix docs-pdf` and
  attached to every GitHub release alongside the ISO.
- Indonesia added to the locale library (80 locales total).
- Loud "this erases your disk / no responsibility for lost data" warnings
  across the install docs.
- The keyboard documentation now shows the actual layer diagrams — base
  (home-row modifiers), navigation and herdr — generated from the same key
  tables kanata uses, in the Kartoza palette, and regenerated as part of
  the docs build so they can't drift.
- `gisnix update --flake` updates flake.lock before rebuilding (every
  input, or just one with `--flake=<input>`), so bumping an input and
  applying it is one command.

### Changed

- voxtype push-to-talk moved from the Menu key to **physical right Ctrl**,
  which exists on every keyboard (Menu does not), so the gesture is the
  same on any host. Documented that transcription runs entirely on the CPU
  via whisper.cpp — no GPU or NPU needed.
- The installer ISO now carries the full `linux-firmware` set (not only the
  redistributable subset), so `nmtui` can see wifi radios whose firmware
  isn't redistributable.

### Fixed

- The docs build no longer fails rendering diagrams into the read-only Nix
  store, and the PDF plugin no longer trips `mkdocs build --strict`.

## [0.17.1] - 2026-09-26

### Fixed

- The install completed the real work — disko, the closure copy,
  `nixos-install`, GRUB — and then failed at the very last step, "copying
  the flake into the new machine", because the system build left a
  `system-toplevel` symlink in the flake work directory and the copy
  followed it into the Nix store. The build now uses `--no-link
  --print-out-paths`, so no symlink is left behind and the install runs
  clean to the end.
- The Docs (GitHub Pages) build no longer fails trying to write a
  regenerated `.mmd` into the read-only Nix store during `nix run
  .#docs-build`; the write is now conditional and non-fatal.

## [0.17.0] - 2026-09-26

### Fixed

- **The installer now completes.** `nixos-install`'s own build step
  (`nix build --store /mnt …#toplevel`) did not reliably copy the system
  closure into the target store — on a real install it left `/mnt`
  without the toplevel, so the post-install chroot died with
  `chroot: failed to run command '/nix/var/nix/profiles/system/activate':
  No such file or directory` and exit 127. The installer now builds the
  toplevel, copies its closure into `/mnt` with an explicit `nix copy`,
  and runs `nixos-install --system` on the prebuilt path. Reproduced and
  the fix verified in isolation before shipping; see AGENTS.md, where the
  explicit copy is now a documented, load-bearing rule.
- Retrying the install within one boot session no longer fails disko —
  a `NIXROOT` pool left imported from an earlier attempt is exported
  first (disko's `--mode destroy` wipes the partition table but does not
  un-import a live pool).
- sshd auto-starts in the `test-install`/`test-boot` QEMU VMs again — the
  condition was `ConditionVirtualization = "qemu"`, but QEMU with KVM
  reports `kvm`; changed to `vm` (still off on bare metal).
- `gisnix test-install`/`test-boot` no longer recurse into themselves —
  the new command rows were minting flake apps that overrode the real
  QEMU apps; the implementations are now `test-install-impl`/`test-boot-impl`.

### Added

- A comprehensive locale library: 78 locales from a single manifest
  (`software/locale/locales.json`) covering the major GIS-using countries
  in native-language and English-desktop variants, generated by
  `utils/gen-locales.py` and read by the installer menu — one source, no
  drift, every glibc name validated.
- Locale is now config-driven and separable. `locale` in a host's
  `config.nix` actually selects the preset (the import was hardcoded
  before), and three optional overrides — `timeZone`, `language`,
  `formatLocale` — change one axis without the others, for keeping your
  language and number formatting while moving just the clock.
- `gisnix locale` — show and change the preset or any per-axis override
  interactively, then rebuild.
- `gisnix makeiso` — build the installer ISO locally, named the way the
  release names its assets.
- `gisnix test-shell` / `gisnix test-logs` — SSH into, or pull
  `/mnt/gisnix-install.log` off, the running install-test VM.
- A "Why gisnix" documentation page covering the distribution's design in
  depth: the QGIS-centred focus, bundles, COSMIC on Wayland,
  ZFS-encryption, the keyboard-first setup with voxtype speech-to-text,
  the bubblewrap-jailed AI tools, reproducibility, and `lib.mkHost`.

### Changed

- `gisnix vm --boot` is disabled for now — its nested disk-image build
  hits a virtiofsd/ZFS `EPERM` that panics the inner builder VM. `gisnix
  vm <host>` (quick boot) is unaffected; use `gisnix test-install` to
  test a real install. The redundant per-host `<host>-vm`/`<host>-bootvm`
  dispatcher entries and the grim/slurp `capture-boot` command are gone.

## [0.16.0] - 2026-09-22

### Added

- The "New machine, or a known profile?" step is skipped when there are
  no bundled host profiles to choose between — that screen's only real
  content is "install an existing profile" vs. the already-selected
  "create a new host," which isn't a choice with nothing to pick from.
  Step numbering compresses to match (no gap in "Step X of Y").
- Buttons get a blue focus bevel (light top/left, dark bottom/right)
  that inverts — sinks in — for the brief moment Enter/click holds them,
  instead of the same flat accent tint every other focusable widget uses.
- `installer/tests/`: 27 regression tests covering the wizard's own
  navigation plumbing, ZFS quota math, generated Nix syntax, and the new
  button styling — added after a real incident (see 0.15.0's crash fix)
  exposed that nothing had ever exercised pushing every registered
  screen. `pytest installer/tests` from the repo root; `pytest` is now
  provisioned in the dev shell alongside `textual`.

### Fixed

- The software-selection screen's bundle stack showed each bundle's full
  `LOAD_BEARING` description under its title, pushing the list well past
  one screen — descriptions dropped, each bundle is now a single-row
  colour bar; order and tone alone carry the "stack" idea.

## [0.15.0] - 2026-09-22

### Added

- Releases now attach a `gisnix-installer-vX.Y.Z.iso` (hard-linked to the
  same build, plus its own `.sha256`) alongside the existing stable
  `gisnix-installer.iso` — grabbing an exact version no longer means
  downloading a same-named file as every other release. The stable name
  is unchanged and still what the docs site's download button points at.

### Fixed

- 0.14.0 crashed with `AttributeError: 'InstallingScreen' object has no
  attribute 'set_step'` right as the wizard reached the Installing step
  on a real (non-mock) install — confirmed on bare metal. `InstallingScreen`
  and `DoneScreen` are plain `Screen` subclasses, not `WizardScreen`, but
  0.14.0's step-counter code called `set_step()` unconditionally on every
  screen in the wizard order, those two included. Guarded with a
  capability check; those two screens simply don't carry a numbered
  badge, which is correct — they never had the card chrome to number in
  the first place.

## [0.14.0] - 2026-09-22

### Added

- ZFS dataset quotas are now sized from the actual disk (`installer/sizing.py`)
  instead of a fixed 20G `/nix` quota — a real desktop/QGIS closure could blow
  straight through that mid-`nixos-install`. A disk too small for the layout
  is now rejected on the storage screen, before disko touches it, instead of
  failing deep inside a chroot with a cryptic error. The install log is also
  now teed to `/mnt/gisnix-install.log` once `/mnt` is the real target root.
- Reshaped wizard visuals: two-tone colour panels on the welcome/storage/
  confirm screens, a "Step X of Y" counter and a small Kartoza corner-logo
  badge (chafa, quad-block glyphs) on every screen, and the console
  font-size slider is back on the welcome screen — rescoped this time so it
  can never leak into the installed system's `console.font` the way it did
  before (see Fixed history for that original bug).
- Animated status indicators: the network-check screen shows a pulsing
  circle that goes gray "Preparing" → orange "Checking" → green "Connected"
  / red "Connection Failed", with an eased shrink-and-grow transition
  between phases. The user-account screen gets matching animated bars — a
  fill bar under the GitHub-username field that resolves once its key
  fetch completes, a live password-strength meter, and a match/mismatch
  bar under the confirm-password field. The same strength/match bars are
  reused on the ZFS encryption passphrase fields.
- The software-selection screen now shows the five default bundles as a
  stack of cards (order and colour convey the base → desktop layering)
  instead of a bulleted list, with copy pointing at `gisnix configure`
  (from `~/nixos-config`, after reboot) for adding more.

### Fixed

- zfs-multi's device list was comma-joined into invalid Nix list syntax
  (`[ "a", "b" ]` instead of the space-separated `[ "a" "b" ]`) — would
  have broken every multi-disk install at evaluation time.
- The network-check screen's own class-level `CSS` was silently replacing
  `WizardScreen`'s entire CSS instead of merging with it (`Screen.CSS`
  doesn't merge across a Python subclass chain) — the card border, title
  row, step badge, and docked button bar all vanished on that one screen.
- Textual's own command-palette affordance (unrelated to this fixed-
  purpose installer) is disabled, and the corner logo badge's size and
  colour fidelity were tuned after live testing on a real console.

## [0.13.3] - 2026-09-22

### Fixed

- v0.13.1's release upload was rejected by GitHub ("size must be less
  than 2147483648") and v0.13.2 inherited the same failure — the ISO
  built fine, but v0.13.1's `installerClosureSeed` change baked in a
  full base+COSMIC+browsers+kanata closure to make a default install
  offline-capable, and that pushed the ISO well past GitHub's
  2GB-per-release-asset limit. Reverted `isoImage.storeContents` to
  `[ ]`: the ISO carries gisnix's flake source (evaluation still works
  offline) but `nixos-install` needs network again to fetch packages.
  Making a real install fully offline needs the ISO hosted somewhere
  without GitHub's size cap — not resolved here.
- Installer network-check screen and the quickstart docs still implied
  an offline install (pre-cached closure) was a supported path — updated
  both to say plainly that the install needs network.

## [0.13.2] - 2026-09-22

### Added

- `docs/developer/releasing.md`: the release process was CI behavior
  nobody had written down — version bump, changelog section, tag, push,
  and what pushing a `v*` tag actually triggers (an unattended ISO build
  and GitHub Release, no separate confirmation step).

### Fixed

- Kanata's herdr<->aerc mode-toggle beep and voxtype's start/stop audio
  cues never played: kanata's own systemd unit is a system service, which
  gets no `XDG_RUNTIME_DIR`, so the bare `pw-play` its `cmd` actions
  invoked had no PipeWire socket to reach and failed silently. Wrapped it
  in a script that finds whichever logged-in user's PipeWire session is
  actually up.

## [0.13.1] - 2026-09-22

### Fixed

- Installer ISO: no wifi radio detected in `nmtui` on real hardware (e.g.
  Framework 13) — the `installation-cd-minimal` base ships no firmware
  blobs, which most laptop wifi/bluetooth chips need before the device
  even shows up. `hardware.enableRedistributableFirmware = true` now set
  on the installer.
- Installer ISO: iPhone USB tethering did nothing — `usbmuxd` was never
  enabled and `libimobiledevice`/`ifuse` were never installed on the live
  environment (every real gisnix host gets these from the
  services-device-mobile bundle; the installer ISO isn't built through
  the bundle system).
- Installer ISO: an offline install failed reaching cache.nixos.org even
  though the ISO carries gisnix's flake source — `isoImage.storeContents`
  was empty, so evaluation worked offline but no actual packages did.
  Now bakes in the closure of the installer's own default bundle
  selection (`hosts/example`, stableCosmic), so a default install needs
  no network; installs that change the bundle selection or add extras
  still need it.
- Installer TUI: focused widgets rendered as a stark white block —
  `text-style: bold reverse` (added to make the built-in 5%-tint focus
  style visible on the virtual console) swaps foreground/background at
  render time, and Textual's default foreground is near-white on a dark
  theme, so every focused field inverted to white-on-dark instead of
  picking up the intended accent-colour highlight. Replaced with plain
  `bold` on top of the existing accent-tinted background/border.

## [0.13.0] - 2026-09-22

### Added

- `screenshot-satty region-repeat` mode: reuses the last interactively
  selected region instead of popping `slurp` again — useful for cropping
  several screenshots of the same on-screen area in a row.

## [0.12.0] - 2026-09-22

### Added

- herdr layer: `s` for herdr's own `edit_scrollback` (opens pane history
  in `$EDITOR` for keyboard-only selection and copy), `r` to toggle
  kanata's own dynamic-macro recorder (slot 0, with a click either way),
  `p` to play it back.

## [0.11.0] - 2026-09-22

### Added

- Audio cues on voxtype push-to-talk: a short rising sound on press, a
  falling one on release — distinct from the herdr<->aerc mode-toggle's
  own beep, so all three stay distinguishable by ear.

## [0.10.2] - 2026-09-22

### Fixed

- The 0.9.2 PDF-default fix wrote `environment.etc."xdg/mimeapps.list"`
  directly, colliding with NixOS's own `config/xdg/mime.nix` (which
  generates that same file from `xdg.mime.defaultApplications`) —
  "conflicting definition values", confirmed on a real rebuild. Switched
  to that option instead.

## [0.10.1] - 2026-09-22

### Fixed

- `kanata-keyboard.nix` failed to evaluate after 0.10.0 added a
  top-level `options` block: NixOS requires the rest of a module's
  attributes wrapped in an explicit `config = {...};` once `options` is
  present alongside it. Confirmed on a real rebuild.

## [0.10.0] - 2026-09-22

### Added

- `kartoza.kanata.aercLayer` — aerc (mail client) macros now share
  herdr's trigger key instead of owning Tab, switched with a caps+space
  chord (hold the trigger key, tap Space while held) via kanata's
  `layer-switch`. A short beep confirms the switch. Same two-base-layer
  shape as the removed "polymorphic base" era, deliberately — see
  `kanata-config.nix`'s own comment for why this one doesn't share that
  scheme's failure mode (a manual toggle instead of automatic focus
  detection). A real option now, not a bare function parameter nothing
  outside `kanata-keyboard.nix` could reach.

## [0.9.2] - 2026-09-22

### Fixed

- Koodo Reader's `.desktop` file claims `application/pdf` (common for
  ebook readers), which silently became the default PDF handler on any
  host taking both `desktop-ebook-readers` and `desktop-base-extras` —
  confirmed on a real machine, PDFs opened in Koodo Reader instead of
  Evince the moment koodo-reader's insecure-package fix let it build for
  the first time. `/etc/xdg/mimeapps.list` now explicitly defaults
  `application/pdf` to Evince.

## [0.9.1] - 2026-09-22

### Fixed

- Push-to-talk itself never ran voxtype: kanata's `cmd voxtype record
  start`/`stop` failed with "No such file or directory" because kanata
  runs as a system service, which doesn't get
  `/run/current-system/sw/bin` on PATH — confirmed on a real machine
  holding Menu/right-Ctrl and watching the command fail in the kanata
  log, despite voxtype being installed and on PATH for an interactive
  shell. Both bindings now use an absolute path to the binary.

## [0.9.0] - 2026-09-22

### Added

- Physical right Ctrl as a second voxtype push-to-talk trigger, alongside
  Menu — for boards with no Menu key (the Framework 16's built-in
  keyboard is one). Hold either, tap either for its normal action
  (context menu / Ctrl). On by default, since voxtypePtt already is.
  Trade-off: a fast Ctrl+<key> chord typed through the right Ctrl key
  specifically can resolve as a hold and trigger push-to-talk instead of
  the modifier — left Ctrl is unaffected, so every shortcut still works
  through that key.

## [0.8.2] - 2026-09-22

### Fixed

- 0.8.1's own fix broke the rebuild it was meant to fix: plainly setting
  `environment.PATH` collided with the default
  `nixos/modules/system/boot/systemd/user.nix` already sets for every
  user service ("conflicting definition values"). Switched to `path =
  [ pkgs.curl ];`, the standard NixOS idiom for adding a binary to a
  systemd unit's search path without replacing it outright.

## [0.8.1] - 2026-09-22

### Fixed

- `voxtype-model-loader` (added in 0.8.0) failed with "Failed to run curl:
  No such file or directory" — a systemd user service's PATH is not
  `/run/current-system/sw/bin`, so curl (which voxtype's own `setup
  --download` shells out to) has to be given to the unit explicitly.
  Confirmed on a real machine: the 0.8.0 fix deployed and ran correctly,
  it just needed this too.

## [0.8.0] - 2026-09-22

Two real bugs found migrating the rest of a real fleet (six more hosts)
onto `mkHost`.

### Fixed

- voxtype crash-loops forever on a fresh install: the daemon hard-fails
  if its whisper.cpp model isn't already on disk, and the only fix was a
  manual `voxtype setup` nobody runs unprompted. Added a
  `voxtype-model-loader` oneshot (mirroring upstream's own home-manager
  module, reimplemented as a plain NixOS `systemd.user.services` entry)
  that downloads the model before the daemon starts, gated on
  `network-online.target`. Confirmed on a real machine: 6609 restarts
  before anyone noticed voice dictation had never worked.
- `kartoza.userEmails` was declared only inside `kanata-email.nix`, so
  any host importing a user file that sets it — without also importing
  kanata — failed with "option does not exist". Moved the declaration to
  `profiles/common.nix` (imported by every host); it's inert unless a
  host also has kanata to read it.

## [0.7.0] - 2026-09-21

Docs-only — no code change. Written up after a real three-host fleet
migration (nix-config's `minimal`, `atoll`, `abyss`) surfaced two gaps.

### Added

- `docs/developer/downstream-flakes.md`: `consumerInputs` was added in
  0.5.0 but never documented; and two real gotchas from that migration —
  `nixpkgs.config` set directly from more than one module (the same
  last-definition-wins issue `kartoza.unfreePackages`/
  `kartoza.insecurePackages` exist to solve), and `boot.zfs.forceImportRoot`
  conflicting with a pre-disko host's own setting.
- `docs/user/index.md`: surfaces voice dictation (push-to-talk, hold-Menu)
  and [Building your fleet](user/fleet.md), neither linked from the user
  guide's own landing page before now.

## [0.6.0] - 2026-09-20

### Added

- `kartoza.insecurePackages` — a proper list option for
  `nixpkgs.config.permittedInsecurePackages`, same shape and same
  reason as the existing `kartoza.unfreePackages`. `nixpkgs.config` is
  a bare, loosely-typed attrs value with no per-key merge behaviour, so
  two files each setting `permittedInsecurePackages` directly collide
  and only one survives — confirmed on a real host taking both
  `desktop-productivity` (Logseq's EOL electron 39) and
  `desktop-ebook-readers` (koodo-reader's EOL electron 41)
  simultaneously: only one of the two permits took effect, and the
  other package refused to evaluate despite its own module already
  trying to allow it.

### Fixed

- `koodo-reader.nix` and `gui-apps.nix` both switched from setting
  `nixpkgs.config.permittedInsecurePackages` directly to
  `kartoza.insecurePackages`, which concatenates instead of colliding.

## [0.5.1] - 2026-09-20

### Fixed

- `koodo-reader` (`desktop-ebook-readers`) permits `electron-41.9.1`,
  EOL and marked insecure by nixpkgs — same pattern already used for
  Logseq's electron 39 in `gui-apps.nix`.

## [0.5.0] - 2026-09-20

### Fixed

- `mkHost`/`mkFleet` accept a `consumerInputs` override — same class of
  gap as the `projectConfig`/`fleet` override in 0.2.0, found the same
  way (a real migration, a real nix eval). Without it, every host file
  a downstream flake writes sees GISNIX's own `inputs` as its `inputs`
  specialArg, so a private input the consumer's own flake declares
  (a vendored flake, a special-purpose kernel pin) comes back "attribute
  missing" — not because it doesn't exist, but because the host was
  handed the wrong flake's inputs entirely.

## [0.4.0] - 2026-09-20

Split Kartoza-internal apps from generically-useful ones — prompted by a
real nix-config migration hitting `pkgs.kartoza-timesheet` missing, and a
direct call on how the split should actually work.

### Added

- `desktop-kartoza-apps` now carries `kartoza-webapps` (23 of the
  original 25 web-app shortcuts — Gmail, Calendar, Meet, LinkedIn,
  ChatGPT, the Kartoza Handbook/Training/GeoCommunity public sites,
  and others — none of them Kartoza-internal) and `baboon.nix`
  (terminal typing-practice game; the package already existed in the
  overlay but nothing installed it, in either repo, until now).
- New opt-in sibling bundle `desktop-kartoza-apps-screencaster`
  (`kartoza-screencaster`, new flake input + overlay entry) —
  experimental (a known upstream build issue), so opt-in rather than
  part of the always-on set.

### Changed

- `desktop-kartoza-apps`'s description no longer says "none of this
  belongs in gisnix" — most of it always did; only two of the original
  25 web apps (an internal ERP, a private Sentry instance) and
  timesheets were ever actually Kartoza-internal, and those never
  moved here.

## [0.3.0] - 2026-09-20

First real downstream fleet migration, in progress — two nix-config hosts
now build through gisnix's own `mkHost`/`mkFleet`.

### Added

- `docs-generate-hosts` (per-host reference pages) now works the same way
  `configure`/`bundles` already did — reads gisnix's published bundle
  metadata, but runs its `nix eval` and writes generated pages against
  the calling flake's own root, not gisnix's checkout.
- `docs/user/fleet.md` — the fresh-install-to-fleet workflow: living with
  one host, turning it into a real repo, adding a second machine,
  `mkFleet`, and the `extraModules` pattern for private content gisnix's
  generic modules can't carry.

### Fixed

- `docs/developer/downstream-flakes.md` described the exact
  `GISNIX_ROOT`/`TARGET_ROOT` gap fixed in 0.2.0 as still open. Rewritten
  with `mkFleet`, the `projectConfig`/`fleet` override, `gisnixRoot`
  usage, and the CA-certificate re-attachment pattern — confirmed
  against a real migration, not just described.

## [0.2.0] - 2026-09-20

Groundwork for consuming gisnix from a real downstream fleet (nix-config),
prompted by starting that migration.

### Added

- `gisnix.lib.mkFleet`: scans a `hostsDir` for subdirectories carrying a
  `config.nix` and builds `nixosConfigurations` for all of them, with a
  shared or per-host `projectConfig`/`fleet`/`extraModules` override.
- `mkHost` and `mkFleet` accept `projectConfig`/`fleet` overrides, both
  defaulting to gisnix's own. Confirmed the hard way while planning
  nix-config's migration: gisnix's `nixosStateVersion` is `"26.05"`,
  nix-config's is `"25.05"`, and gisnix's `config.nix` is missing fields
  nix-config's own modules read directly — using `mkHost` unmodified on a
  real nix-config host would have silently changed values or hard-failed
  on a missing attribute.

### Fixed

- `configure`/`bundles` hard-refused to run outside a gisnix checkout, and
  `configure.sh` shelled out to a bare relative `utils/configure.py` path
  that only ever resolved by accident. Split `GISNIX_ROOT` (bundle
  catalogue, always gisnix's own tree) from `TARGET_ROOT` (a host's own
  files, always the caller's cwd) throughout the Python side; both
  commands now work from any consumer's own directory. Verified against a
  scratch directory with no gisnix checkout in it at all.

## [0.1.0] - 2026-09-20

First tagged version. First confirmed end-to-end install in a VM: disk
partitioning, ZFS-encrypted root, bootloader, first boot, ZFS passphrase
unlock, and a working COSMIC desktop login — the milestone the rest of
this project builds on.

### Added

- Kartoza-branded Python/Textual installer, mock and live modes.
- GitHub-username SSH key import on the user-account step.
- Bundle registry (`software/`) with `gisnix configure`/`bundles`/`create-host`.
- `gisnix.lib.mkHost`, consumable from a downstream flake.
- Push-to-talk voice-to-text (voxtype) on hold-Menu, wired through kanata.
- `AGENTS.md` for both this repo and nix-config.

### Fixed

- Kanata config bugs that could block install builds outright.
- `install-grub.sh` hangs caused by `useOSProber` scanning the live ISO's
  own CD-ROM device.
- Default install bundle bloat (`desktop-base-extras`, `zfs-backup` pulled
  into every install regardless of bundle choice).
- Root account locked in emergency mode after `nixos-install --no-root-passwd`.
- Installed system's console font stuck at an unreadably small default.
- `boot.zfs.forceImportRoot = false` caused every install's first boot to
  fail importing its own freshly created pool (hostid mismatch between the
  live installer environment and the installed system).
- `~/.config` left owned by root after dotfile-deploying activation
  scripts, blocking COSMIC's first-run config creation.
