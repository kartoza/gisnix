# COSMIC community extensions and panel applets
#
# The cosmic-ext-* packages are community cosmic-utils builds. They are NOT in
# cache.nixos.org or cosmic.cachix.org, so every one of them SOURCE BUILDS.
# That is what made bay's first upgrade appear to hang, and it is why they are
# a bundle of their own rather than part of the desktop: a machine can now run
# COSMIC without committing to a Rust toolchain's worth of compilation.
#
# They were split out of packages.nix, which still holds the desktop itself —
# the core applications, the Kartoza App Library icon, and the screenshot and
# GIF-recording glue.
#
# cosmic-ext-enroll comes too. Its comment in packages.nix said it "cannot
# live in a separate module" because it is built in that file's let block;
# that was only true while the list using it lived in the same file.
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.kartoza.cosmic;
  # COSMIC packages come from nixpkgs-unstable via overlay
  cosmicPkgs = pkgs;
  cosmic-ext-enroll = cosmicPkgs.rustPlatform.buildRustPackage {
    pname = "cosmic-ext-enroll";
    version = "1.0.9";

    src = cosmicPkgs.fetchFromGitHub {
      owner = "cosmic-utils";
      repo = "enroll";
      tag = "1.0.9";
      hash = "sha256-nceG4HhOJSHQL8ECzhsi+As8gBe3zpf/EjBrD4TybDo=";
    };

    cargoHash = "sha256-frQCMhtUKKPmE/iMFOVr32eFRbMovztE7DW9ZnH0QOE=";

    nativeBuildInputs = with cosmicPkgs; [
      libcosmicAppHook
      just
      git
    ];

    # vergen needs these to avoid calling git during the build
    VERGEN_GIT_COMMIT_DATE = "2024-01-01";
    VERGEN_GIT_SHA = "release";

    postPatch = ''
      mkdir -p resources
      if [ ! -f resources/org.cosmic_utils.Enroll.desktop ]; then
        cat > resources/org.cosmic_utils.Enroll.desktop <<EOF
      [Desktop Entry]
      Name=Enroll
      Comment=Fingerprint enrollment for COSMIC
      Exec=cosmic-utils-enroll
      Icon=org.cosmic_utils.Enroll
      Terminal=false
      Type=Application
      Categories=Settings;HardwareSettings;
      EOF
      fi
      if [ ! -f resources/org.cosmic_utils.Enroll.metainfo.xml ]; then
        cat > resources/org.cosmic_utils.Enroll.metainfo.xml <<EOF
      <?xml version="1.0" encoding="UTF-8"?>
      <component type="desktop-application">
        <id>org.cosmic_utils.Enroll</id>
        <name>Enroll</name>
        <summary>Fingerprint enrollment for COSMIC</summary>
        <metadata_license>CC0-1.0</metadata_license>
        <project_license>MPL-2.0</project_license>
      </component>
      EOF
      fi
    '';

    dontUseJustBuild = true;
    dontUseJustCheck = true;

    justFlags = [
      "--set"
      "prefix"
      (placeholder "out")
      "--set"
      "bin-src"
      "target/${cosmicPkgs.stdenv.hostPlatform.rust.cargoShortTarget}/release/cosmic-utils-enroll"
    ];

    meta = {
      description = "GUI for fprintd fingerprint enrollment on COSMIC desktop";
      homepage = "https://github.com/cosmic-utils/enroll";
      license = lib.licenses.mpl20;
      mainProgram = "cosmic-utils-enroll";
      platforms = lib.platforms.linux;
    };
  };
in
{
  config = mkIf cfg.enable {
    environment.systemPackages =
      (with cosmicPkgs; [
        # Extensions
        cosmic-ext-calculator # Calculator
        cosmic-ext-ctl # CLI for COSMIC configuration
        cosmic-ext-tweaks # Tweaking tool
        # Panel applets
        cosmic-ext-applet-minimon # monitoring applet for panel
        cosmic-ext-applet-sysinfo # CPU / RAM / etc panel applet
        cosmic-ext-applet-weather # Weather panel applet
        cosmic-ext-applet-caffeine # stop screen from sleeping
        cosmic-ext-applet-external-monitor-brightness
        cosmic-ext-applet-privacy-indicator
      ])
      # Fingerprint enrolment GUI, built from source in the let block above.
      ++ [ cosmic-ext-enroll ];
  };
}
