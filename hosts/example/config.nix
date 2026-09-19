{
  # Example host — installed by default with the minimal base system plus a
  # minimal COSMIC desktop and kanata keyboard remapping (base,
  # desktop-environments-cosmic, desktop-browsers, services-system,
  # services-device-input-kanata). Copy this directory as the starting
  # point for your own host: `gisnix create-host <name>` does this for you.
  #
  # Per-host settings consumed via the `hostConfig` specialArg (see mkHost in
  # flake.nix). Nothing host-specific is needed here yet — the FQDN comes from
  # `networking.hostName` + `projectConfig.domain`, not from this file.

  # Software bundles — the package sets this machine installs. A bundle is a
  # directory under software/; see docs/references/bundles.md, or
  # `gisnix bundles`, for what each one holds. Implications resolve
  # automatically, so asking for desktop-gis brings in the COSMIC desktop it
  # needs to display QGIS.
  #
  # Every bundle is listed. Uncomment a line to take it, comment it out to
  # drop it, or run `gisnix configure` and tick the boxes.
  bundles = [
    # ── Base ──────────────────────────────────────────────────────────────
    # Everything a machine needs to be a usable machine: ZFS root and its
    # bootloader, the memory guard a swapless host depends on, the login
    # shell, the terminal emulator and the core command-line tools. A host
    # taking only this is minimal but not crippled.
    #
    # Required: `gisnix configure` will not remove this from a host that has it
    # — this is the ZFS root and its bootloader. Removing it does not make
    # the machine smaller, it makes it unbootable.
    "base"

    # ── Terminal ──────────────────────────────────────────────────────────
    # AI assistants, each bubblewrap-sandboxed so a compromised one cannot
    # reach your SSH agent. Opt-in: local-llm alone pulls the ROCm stack
    # into the closure.
    # "terminal-ai"

    # Neovim, configured through nvf, with the EDITOR and vim/vi wiring that
    # goes with it. Its own bundle rather than part of terminal-tuis because
    # the plugin set builds from source — a crates.io fetch that has failed
    # on hosts whose store cannot reach this flake's inputs, and the reason
    # a host behind such a store takes the rest of the TUIs without it.
    # "terminal-editor"

    # Full-screen terminal applications: yazi and Midnight Commander for
    # files, lazygit for git, aerc for mail, btop and friends for watching
    # the machine, khal and khard for calendars and contacts. nmtui is not
    # here because it is not a package — it ships inside networkmanager,
    # which services-network enables.
    # "terminal-tuis"

    # ── Desktop ───────────────────────────────────────────────────────────
    # Web browsers.
    "desktop-browsers"

    # Talking to people and moving files between machines you own.
    # "desktop-comms"

    # E-book readers and library management.
    # "desktop-ebook-readers"

    # Desktop-environment-agnostic pieces every graphical session needs:
    # fonts, file manager, clipboard, notifications, document viewers,
    # screen capture.
    # "desktop-essentials"

    # Games and emulators.
    # "desktop-games"

    # QGIS and the geospatial desktop, on the packaged binary channels.
    # Several QGIS versions install side by side deliberately — that is how
    # a GIS workstation is used.
    # "desktop-gis"

    # ── Desktop · GIS ─────────────────────────────────────────────────────
    # QGIS compiled from the git heads — master (dev), the latest release
    # branch, and the LTR branch — for testing in-progress bug fixes before
    # they ship. Opt-in: hours of build time on top of the binary channels.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # hours of build time; the binary channels already cover normal use.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # hours of build time; the binary channels already cover normal use.
    # QGIS compiled from source or git. Opt-in: hours of build time for the
    # same application, when the binary channels are preferred.
    # "desktop-gis-source-builds"

    # QGIS 1.8 pinned (1.8.0, the last 1.8.x that nixpkgs shipped), a
    # vintage Qt4/Python2 build with no extra python packages; may no longer
    # evaluate or have every binary cached.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # a frozen historical QGIS; take it only when a project needs this exact
    # series.
    # "desktop-gis-versions-qgis-1-8"

    # QGIS 2.10 pinned (2.10.1, the last 2.10.x that nixpkgs shipped), a
    # vintage Qt4/Python2 build with no extra python packages; may no longer
    # evaluate or have every binary cached.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # a frozen historical QGIS; take it only when a project needs this exact
    # series.
    # "desktop-gis-versions-qgis-2-10"

    # QGIS 2.16 pinned (2.16.2, the last 2.16.x that nixpkgs shipped), a
    # vintage Qt4/Python2 build with no extra python packages; may no longer
    # evaluate or have every binary cached.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # a frozen historical QGIS; take it only when a project needs this exact
    # series.
    # "desktop-gis-versions-qgis-2-16"

    # QGIS 2.18 pinned (2.18.28, the last 2.18.x that nixpkgs shipped), a
    # vintage Qt4/Python2 build with no extra python packages; may no longer
    # evaluate or have every binary cached.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # a frozen historical QGIS; take it only when a project needs this exact
    # series.
    # "desktop-gis-versions-qgis-2-18"

    # QGIS 2.4 pinned (2.4.0, the last 2.4.x that nixpkgs shipped), a
    # vintage Qt4/Python2 build with no extra python packages; may no longer
    # evaluate or have every binary cached.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # a frozen historical QGIS; take it only when a project needs this exact
    # series.
    # "desktop-gis-versions-qgis-2-4"

    # QGIS 2.6 pinned (2.6.1, the last 2.6.x that nixpkgs shipped), a
    # vintage Qt4/Python2 build with no extra python packages; may no longer
    # evaluate or have every binary cached.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # a frozen historical QGIS; take it only when a project needs this exact
    # series.
    # "desktop-gis-versions-qgis-2-6"

    # QGIS 2.8 pinned (2.8.2, the last 2.8.x that nixpkgs shipped), a
    # vintage Qt4/Python2 build with no extra python packages; may no longer
    # evaluate or have every binary cached.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # a frozen historical QGIS; take it only when a project needs this exact
    # series.
    # "desktop-gis-versions-qgis-2-8"

    # QGIS 3.10 pinned (3.10.13, the last 3.10.x that nixpkgs shipped),
    # installed with the standard python packages from its own pinned
    # nixpkgs — pure binary-cache hits, no source builds.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # a frozen historical QGIS; take it only when a project needs this exact
    # series.
    # "desktop-gis-versions-qgis-3-10"

    # QGIS 3.16 pinned (3.16.14, the last 3.16.x that nixpkgs shipped),
    # installed with the standard python packages from its own pinned
    # nixpkgs — pure binary-cache hits, no source builds.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # a frozen historical QGIS; take it only when a project needs this exact
    # series.
    # "desktop-gis-versions-qgis-3-16"

    # QGIS 3.22 pinned (3.22.16, the last 3.22.x that nixpkgs shipped),
    # installed with the standard python packages from its own pinned
    # nixpkgs — pure binary-cache hits, no source builds.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # a frozen historical QGIS; take it only when a project needs this exact
    # series.
    # "desktop-gis-versions-qgis-3-22"

    # QGIS 3.24 pinned (3.24.2, the last 3.24.x that nixpkgs shipped),
    # installed with the standard python packages from its own pinned
    # nixpkgs — pure binary-cache hits, no source builds.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # a frozen historical QGIS; take it only when a project needs this exact
    # series.
    # "desktop-gis-versions-qgis-3-24"

    # QGIS 3.26 pinned (3.26.2, the last 3.26.x that nixpkgs shipped),
    # installed with the standard python packages from its own pinned
    # nixpkgs — pure binary-cache hits, no source builds.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # a frozen historical QGIS; take it only when a project needs this exact
    # series.
    # "desktop-gis-versions-qgis-3-26"

    # QGIS 3.28 pinned (3.28.15, the last 3.28.x that nixpkgs shipped),
    # installed with the standard python packages from its own pinned
    # nixpkgs — pure binary-cache hits, no source builds.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # a frozen historical QGIS; take it only when a project needs this exact
    # series.
    # "desktop-gis-versions-qgis-3-28"

    # QGIS 3.32 pinned (3.32.3, the last 3.32.x that nixpkgs shipped),
    # installed with the standard python packages from its own pinned
    # nixpkgs — pure binary-cache hits, no source builds.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # a frozen historical QGIS; take it only when a project needs this exact
    # series.
    # "desktop-gis-versions-qgis-3-32"

    # QGIS 3.34 pinned (3.34.15, the last 3.34.x that nixpkgs shipped),
    # installed with the standard python packages from its own pinned
    # nixpkgs — pure binary-cache hits, no source builds.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # a frozen historical QGIS; take it only when a project needs this exact
    # series.
    # "desktop-gis-versions-qgis-3-34"

    # QGIS 3.36 pinned (3.36.3, the last 3.36.x that nixpkgs shipped),
    # installed with the standard python packages from its own pinned
    # nixpkgs — pure binary-cache hits, no source builds.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # a frozen historical QGIS; take it only when a project needs this exact
    # series.
    # "desktop-gis-versions-qgis-3-36"

    # QGIS 3.38 pinned (3.38.3, the last 3.38.x that nixpkgs shipped),
    # installed with the standard python packages from its own pinned
    # nixpkgs — pure binary-cache hits, no source builds.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # a frozen historical QGIS; take it only when a project needs this exact
    # series.
    # "desktop-gis-versions-qgis-3-38"

    # QGIS 3.4 pinned (3.4.8, the last 3.4.x that nixpkgs shipped),
    # installed with the standard python packages from its own pinned
    # nixpkgs — pure binary-cache hits, no source builds.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # a frozen historical QGIS; take it only when a project needs this exact
    # series.
    # "desktop-gis-versions-qgis-3-4"

    # QGIS 3.40 pinned (3.40.15, the last 3.40.x that nixpkgs shipped),
    # installed with the standard python packages from its own pinned
    # nixpkgs — pure binary-cache hits, no source builds.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # a frozen historical QGIS; take it only when a project needs this exact
    # series.
    # "desktop-gis-versions-qgis-3-40"

    # QGIS 3.42 pinned (3.42.3, the last 3.42.x that nixpkgs shipped),
    # installed with the standard python packages from its own pinned
    # nixpkgs — pure binary-cache hits, no source builds.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # a frozen historical QGIS; take it only when a project needs this exact
    # series.
    # "desktop-gis-versions-qgis-3-42"

    # QGIS 3.44 pinned (3.44.12, the last 3.44.x that nixpkgs shipped),
    # installed with the standard python packages from its own pinned
    # nixpkgs — pure binary-cache hits, no source builds.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # a frozen historical QGIS; take it only when a project needs this exact
    # series.
    # "desktop-gis-versions-qgis-3-44"

    # QGIS 3.8 pinned (3.8.0, the last 3.8.x that nixpkgs shipped),
    # installed with the standard python packages from its own pinned
    # nixpkgs — pure binary-cache hits, no source builds.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # a frozen historical QGIS; take it only when a project needs this exact
    # series.
    # "desktop-gis-versions-qgis-3-8"

    # QGIS 4.0 pinned (4.0.3, the last 4.0.x that nixpkgs shipped),
    # installed with the standard python packages from its own pinned
    # nixpkgs — pure binary-cache hits, no source builds.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # a frozen historical QGIS; take it only when a project needs this exact
    # series.
    # "desktop-gis-versions-qgis-4-0"

    # ── Desktop ───────────────────────────────────────────────────────────
    # Kartoza's public desktop tools: endpoint monitoring (Gatus Monitor).
    # "desktop-kartoza-apps"

    # Audio and video creation: screen recording and streaming, and editors
    # tracking nixpkgs-unstable.
    # "desktop-multimedia"

    # Getting work done: the office and creative suite, mail and calendar,
    # and screen annotation for presentations.
    # "desktop-productivity"

    # Screens from somewhere else: remote desktop, phone mirroring, and
    # receiving AirPlay.
    # "desktop-remote"

    # The COSMIC desktop itself: compositor, greeter, core applications, the
    # Kartoza App Library icon, the screenshot and GIF-recording glue, and
    # the SSH/GPG agent wiring that goes with a graphical session. The
    # community extensions and applets are a separate bundle, because they
    # source build.
    "desktop-environments-cosmic"

    # ── Desktop · Environments · Cosmic ───────────────────────────────────
    # COSMIC's community extensions and panel applets: calculator, tweaks,
    # cosmic-ctl, the weather, sysinfo, caffeine, brightness and privacy-
    # indicator applets, and the fingerprint enrolment GUI.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # every one of these source builds. They are community cosmic-utils
    # packages, in neither cache.nixos.org nor cosmic.cachix.org, and
    # compiling them is what made bay's first upgrade appear to hang.
    # "desktop-environments-cosmic-extensions"

    # ── Services ──────────────────────────────────────────────────────────
    # Hardware every machine benefits from: Bluetooth and firmware updates.
    # Anything depending on what is actually plugged in is a sub-bundle.
    "services-device"

    # ── Services · Device ─────────────────────────────────────────────────
    # Vendor input hardware: Dygma/Bazecor configurator, Razer RGB/DPI,
    # generic mouse configurators. Kanata's own keyboard remapping is the
    # services-device-input-kanata bundle instead — it needs no vendor
    # hardware and ships on by default, unlike the daemons and kernel
    # modules here.
    # "services-device-input"

    # Kanata keyboard remapping: home-row mods, a navigation layer, and
    # layout-aware chords (see docs/user/keyboard.md). Generic — matches
    # every keyboard, needs no vendor hardware. On by default; a sibling of
    # services-device-input rather than a child of it, so this stays on
    # when the vendor-specific tools there (Bazecor, OpenRazer, Piper) are
    # turned off.
    "services-device-input-kanata"

    # Phones and tablets: iOS mounting and display control.
    # "services-device-mobile"

    # Hardware only some machines have: fingerprint readers, scanners,
    # graphics tablets, game controllers. Each pulls in daemons a host
    # without the device has no use for — and biometrics can affect whether
    # you can log in, which is why this is never taken by default.
    #
    # Opt-in: never added by `gisnix configure` when you take the group above —
    # biometrics can affect whether you can log in, and the rest are daemons
    # for hardware most hosts do not have.
    # "services-device-peripherals"

    # CUPS and printer drivers. Its own bundle despite holding one module:
    # printing turned out to be the peripheral most hosts actually want, and
    # folding it into the opt-in peripherals group silently cost five
    # machines their printers. A singleton is the lesser problem.
    # "services-device-printing"

    # ── Services ──────────────────────────────────────────────────────────
    # DNS filtering: blocky as the local resolver, plus the firewall rules
    # that stop applications bypassing it over DoH. Fleet-wide policy.
    # "services-dns"

    # Network presence: mDNS service discovery, and the overlay VPN.
    # Tailscale here is being replaced by NetBird.
    # "services-network"

    # File synchronisation between machines and to cloud storage.
    # "services-sync"

    # What every machine needs without exception: CA trust, the fleet's
    # /etc/hosts, kernel hardening, sshd, the unfree allow-list, audio and
    # Flatpak.
    #
    # Required: `gisnix configure` will not remove this from a host that has it
    # — sshd, CA trust and kernel hardening. Removing it from a machine you
    # reach over the network is how you stop being able to reach it.
    "services-system"

    # ── Services · System ─────────────────────────────────────────────────
    # The text console: login banner, message of the day, and fonts that
    # make a high-DPI TTY readable.
    # "services-system-console"

    # Power management: battery thresholds, suspend behaviour, SSD trim.
    # Laptop concerns.
    # "services-system-power"

    # Filesystem support and snapshot scheduling: NTFS for external drives,
    # sanoid for automatic ZFS snapshots.
    # "services-system-storage"

    # ── Services ──────────────────────────────────────────────────────────
    # Running things that are not native to this machine: containers,
    # virtual machines, cross-architecture emulation, Windows compatibility.
    # "services-virtualisation"

    # ── Security ──────────────────────────────────────────────────────────
    # Credentials and keys: the password manager, and the hardware tokens
    # with their udev rules and daemons. Grouped by what they are for rather
    # than whether they are hardware.
    # "security"
  ];

  # GRUB and Plymouth branding. Alternatives — a host boots with one splash,
  # and its GRUB menu matches it. Each member is the Plymouth/GRUB pair,
  # because a Kartoza menu handing over to a QGIS splash reads as a fault.
  bootTheme = "kartoza";
}
