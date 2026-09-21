{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.kartoza-webapps;

  # App definitions - add new apps here
  apps = {
    aistudio = {
      name = "Google AI Studio";
      url = "https://aistudio.google.com";
      categories = [
        "Network"
        "Office"
      ];
      icon = "aistudio.svg";
    };
    bluesky = {
      name = "BlueSky";
      url = "https://bsky.app";
      categories = [
        "Network"
        "Office"
      ];
      icon = "bluesky.svg";
    };
    chat-gpt = {
      name = "Chat GPT";
      url = "https://chatgpt.com";
      categories = [
        "Network"
        "Office"
      ];
      icon = "chat-gpt.svg";
    };
    deepseek = {
      name = "DeepSeek";
      url = "https://chat.deepseek.com/";
      categories = [
        "Network"
        "Office"
      ];
      icon = "deepseek.svg";
    };
    drawdb = {
      name = "DrawDB";
      url = "https://www.drawdb.app";
      categories = [
        "Network"
        "Office"
      ];
      icon = "drawdb.png";
    };
    google-calendar = {
      name = "Google Calendar";
      url = "https://calendar.google.com";
      categories = [
        "Network"
        "Office"
      ];
      icon = "google-calendar.svg";
    };
    google-chat = {
      name = "Google Chat";
      url = "https://chat.google.com";
      categories = [
        "Network"
        "Office"
      ];
      icon = "google-chat.svg";
    };
    google-drive = {
      name = "Google Drive";
      url = "https://drive.google.com";
      categories = [
        "Network"
        "Office"
      ];
      icon = "google-drive.svg";
    };
    google-mail = {
      name = "GMail";
      url = "https://mail.google.com";
      categories = [
        "Network"
        "Office"
      ];
      icon = "google-mail.svg";
    };
    google-meet = {
      name = "Google Meet";
      url = "https://meet.google.com";
      categories = [
        "Network"
        "Video"
      ];
      icon = "google-meet.svg";
    };
    instagram = {
      name = "Instagram";
      url = "https://www.instagram.com/";
      categories = [
        "Network"
        "Graphics"
      ];
      icon = "instagram.svg";
    };
    kartoza-geocommunity = {
      name = "My Geo Community";
      url = "https://mygeocommunity.org";
      categories = [
        "Network"
        "Science"
      ];
      icon = "kartoza-geocommunity.svg";
    };
    kartoza-handbook = {
      name = "Kartoza Handbook";
      url = "https://kartoza.github.io/TheKartozaHandbook/";
      categories = [
        "Network"
        "Office"
      ];
      icon = "kartoza-handbook.svg";
    };
    kartoza-ntfy = {
      name = "Kartoza Ntfy";
      url = "https://ntfy.sh/app";
      categories = [
        "Network"
        "Office"
      ];
      icon = "kartoza-ntfy.svg";
    };
    kartoza-training = {
      name = "Kartoza Training";
      url = "https://training.kartoza.com";
      categories = [
        "Network"
        "Education"
      ];
      icon = "kartoza-training.svg";
    };
    lichess = {
      name = "Lichess";
      url = "https://lichess.org";
      categories = [
        "Network"
        "Game"
      ];
      icon = "lichess.svg";
    };
    linkedin = {
      name = "LinkedIn";
      url = "https://www.linkedin.com/";
      categories = [
        "Network"
        "Office"
      ];
      icon = "linkedin.svg";
    };
    ms-teams = {
      name = "Microsoft Teams";
      url = "https://teams.live.com";
      categories = [
        "Network"
        "Office"
      ];
      icon = "nix.svg";
    };
    nix-search = {
      name = "Nix Package Search";
      url = "https://search.nixos.org";
      categories = [
        "Network"
        "Office"
      ];
      icon = "nix-search.svg";
    };
    proton-mail = {
      name = "Proton Mail";
      url = "https://mail.proton.me";
      categories = [
        "Network"
        "Office"
      ];
      icon = "proton-mail.svg";
    };
    pypi = {
      name = "PyPi";
      url = "https://pypi.org/";
      categories = [
        "Network"
        "Office"
      ];
      icon = "pypi.svg";
    };
    svg-repo = {
      name = "SVG Repo";
      url = "https://www.svgrepo.com/";
      categories = [
        "Network"
        "Graphics"
      ];
      icon = "svg-repo.svg";
    };
    whatsapp = {
      name = "WhatsApp Web";
      url = "https://web.whatsapp.com/";
      categories = [
        "Network"
        "Office"
      ];
      icon = "whatsapp.svg";
    };
  };

  enabledApps =
    if cfg.enableAll then apps else lib.filterAttrs (appId: _: cfg.apps.${appId}.enable) cfg.apps;

  # Build a shell script wrapper for each app
  mkLauncher =
    appId: appDef:
    let
      wmClass = lib.escapeShellArg (mkWmClass appDef);
    in
    pkgs.writeShellScriptBin appId ''
      # Find a Chromium-based browser
      for browser in chromium chromium-browser google-chrome google-chrome-stable brave-browser; do
        if command -v "$browser" >/dev/null 2>&1; then
          exec "$browser" \
            --app=${lib.escapeShellArg appDef.url} \
            --class=${wmClass} \
            --name=${wmClass} \
            --user-data-dir="$HOME/.config/kartoza-webapps/${appId}" \
            --disable-extensions \
            --ozone-platform-hint=auto \
            --force-dark-mode \
            --enable-features=WebUIDarkMode
        fi
      done
      echo "Error: No Chromium-based browser found." >&2
      exit 1
    '';

  # Built once, referenced twice: installed into systemPackages, and named by
  # absolute path in each desktop entry's Exec= below.
  #
  # The bare name is not safe to put in Exec=. A launcher is a plain binary in
  # the system profile, and any package installed into a *user* profile that
  # ships the same name shadows it — per-user profiles come first on PATH.
  # protonmail-desktop (users/tim.nix) ships bin/proton-mail, exactly the name
  # this module's Proton launcher uses, so `Exec=proton-mail` started the
  # Electron app instead. That window's app_id is not the URL-derived string
  # the desktop file is named after, so the panel had nothing to match and the
  # webapp showed a generic icon — a packaging collision that reads as a
  # missing icon.
  launchers = lib.mapAttrs mkLauncher enabledApps;

  # Icon file extension
  iconExt = icon: if lib.hasSuffix ".png" icon then ".png" else ".svg";

  # Installed icon name, namespaced.
  #
  # These used to be installed under the bare appId ("google-meet"), which
  # collides with icons the active theme already ships. XDG icon lookup
  # searches the current theme (Papirus, set in profiles/kartoza.nix) and its
  # parents *before* falling back to hicolor, so Papirus's own google-meet,
  # google-chat, google-drive, proton-mail and whatsapp icons silently won
  # over the curated assets here. Prefixing puts them in a namespace no theme
  # ships, so hicolor is always the only match.
  iconName = appId: "kartoza-webapp-${appId}";

  # Where an icon is installed in the hicolor tree. "scalable" is reserved for
  # vectors — a PNG there is a spec violation that some icon loaders honour by
  # refusing to scale it. Raster icons go in a sized directory instead.
  iconDir =
    icon:
    if lib.hasSuffix ".png" icon then
      "share/icons/hicolor/64x64/apps"
    else
      "share/icons/hicolor/scalable/apps";

  # Chromium on Wayland ignores --class/--name for --app= windows and
  # derives the xdg app_id from the URL and profile directory instead:
  #   chrome-<host>_<path, with "/" replaced by "_">-Default
  # (web_app::GenerateApplicationNameFromURL in Chromium; e.g.
  # https://training.kartoza.com -> chrome-training.kartoza.com__-Default).
  # COSMIC's panel matches running windows to desktop entries by app_id,
  # so the desktop file must be *named* after that string or running
  # webapps get a generic icon — the launcher reads entries directly and
  # was unaffected. We pass the same string as --class so X11 WM_CLASS
  # and Wayland app_id agree and one desktop file covers both.
  mkWmClass =
    appDef:
    let
      stripped = lib.removePrefix "https://" (lib.removePrefix "http://" appDef.url);
      parts = lib.splitString "/" stripped;
      host = builtins.head parts;
      path = "/" + lib.concatStringsSep "/" (builtins.tail parts);
    in
    "chrome-${host}_${lib.replaceStrings [ "/" ] [ "_" ] path}-Default";

  # Package containing desktop files and icons for all enabled apps.
  #
  # Do NOT add NoDisplay=true to these entries, however tempting it is to keep
  # a match-only entry out of the launcher: on COSMIC, hidden entries are
  # skipped during window matching too, so the running window loses its icon
  # and falls back to the generic cog. See ./README.md.
  webappsDesktopItems = pkgs.runCommand "kartoza-webapps-desktop" { } (
    ''
      mkdir -p $out/share/applications \
               $out/share/icons/hicolor/scalable/apps \
               $out/share/icons/hicolor/64x64/apps
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (
        appId: appDef:
        let
          wmClass = mkWmClass appDef;
        in
        ''
          cat > $out/share/applications/${wmClass}.desktop << 'DESKTOP'
          [Desktop Entry]
          Type=Application
          Name=${appDef.name}
          Comment=Desktop launcher for ${appDef.name}
          Exec=${launchers.${appId}}/bin/${appId}
          Icon=${iconName appId}
          Terminal=false
          Categories=${lib.concatStringsSep ";" appDef.categories};
          StartupWMClass=${wmClass}
          DESKTOP
          cp ${./assets/${appDef.icon}} $out/${iconDir appDef.icon}/${iconName appId}${iconExt appDef.icon}
        ''
      ) enabledApps
    )
  );
in
{
  options.programs.kartoza-webapps = {
    enableAll = lib.mkEnableOption "all Kartoza web applications";

    apps = lib.mkOption {
      type = lib.types.submodule {
        options = builtins.mapAttrs (
          appId: appDef:
          lib.mkOption {
            type = lib.types.submodule {
              options = {
                enable = lib.mkEnableOption "the ${appDef.name} desktop application";
              };
            };
            default = { };
          }
        ) apps;
      };
      default = { };
      description = "Kartoza web applications to enable system-wide";
    };
  };

  # enableAll implies enabledApps != { }, so one check covers both.
  config = lib.mkIf (enabledApps != { }) {
    environment.systemPackages = lib.attrValues launchers ++ [ webappsDesktopItems ];
  };
}
