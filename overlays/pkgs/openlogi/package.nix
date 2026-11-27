# OpenLogi (https://openlogi.org) — local-first Logitech HID++ device
# control: button remap, DPI, SmartShift. No account, no telemetry; config
# lives in a plain TOML file. Replaces the role Solaar used to play before
# its removal — see software/services/device/input/piper.nix for that
# history and software/services/device/input/openlogi.nix for the module
# that wires this package in.
#
# Not in nixpkgs; upstream ships no source tarball release, only prebuilt
# .deb/.rpm/.pkg.tar.zst/.flatpak. Repackaging the .deb with dpkg-deb -x is
# the standard nixpkgs idiom for this.
#
# Update: bump version, then take the new hash from
#   curl -s https://api.github.com/repos/AprilNEA/OpenLogi/releases/latest \
#     | jq -r '.assets[] | select(.name == "openlogi-v<version>-linux-amd64.deb") | .browser_download_url'
# and convert the published SHA256SUMS entry to SRI with
#   nix hash convert --to sri --hash-algo sha256 <hex-digest>
{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  xkbcommon,
  xorg,
  libGL,
  vulkan-loader,
  wayland,
}:

stdenv.mkDerivation rec {
  pname = "openlogi";
  version = "0.9.0";

  src = fetchurl {
    url = "https://github.com/AprilNEA/OpenLogi/releases/download/v${version}/openlogi-v${version}-linux-amd64.deb";
    hash = "sha256-pT1IW6Jdsdxxw9Sfgu7gzpuotEnwWlDxEIlbMQ7yzvs=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
  ];

  # The CLI/agent binaries link only libc/libm/libgcc_s; the GUI binaries
  # (openlogi-desktop, openlogi-overlay) also need xkbcommon/xcb for
  # keyboard handling in their windows.
  buildInputs = [
    stdenv.cc.cc.lib
    xkbcommon
    xorg.libxcb
  ];

  unpackPhase = ''
    dpkg-deb -x $src .
  '';

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -m 755 -D \
      usr/bin/openlogi usr/bin/openlogi-agent usr/bin/openlogi-desktop usr/bin/openlogi-overlay \
      -t $out/bin

    install -m 444 -D usr/share/applications/openlogi.desktop -t $out/share/applications
    cp -r usr/share/icons $out/share/

    install -m 444 -D usr/share/licenses/openlogi/LICENSE-MIT usr/share/licenses/openlogi/LICENSE-APACHE \
      -t $out/share/licenses/openlogi

    install -m 444 -D etc/udev/rules.d/70-openlogi.rules $out/lib/udev/rules.d/70-openlogi.rules

    runHook postInstall
  '';

  # openlogi-desktop and openlogi-overlay render through GPUI (the same
  # engine zed-editor uses) and dlopen Vulkan/EGL/Wayland at runtime rather
  # than linking them — autoPatchelfHook only patches the declared NEEDED
  # entries (libxkbcommon/libxcb/libc), so the GL/Vulkan/Wayland stack has
  # to be added to the rpath by hand, same as nixpkgs' zed-editor package.
  postFixup = ''
    patchelf --add-rpath ${
      lib.makeLibraryPath [
        libGL
        vulkan-loader
        wayland
      ]
    } $out/bin/openlogi-desktop $out/bin/openlogi-overlay
  '';

  meta = {
    description = "Logitech HID++ device control — remap buttons, DPI, and SmartShift";
    longDescription = ''
      Local-first alternative to Logi Options+. No account, no telemetry;
      configuration lives in a plain TOML file
      (~/.config/openlogi/config.toml). Covers HID++ 2.0 mice, keyboards and
      cameras over Bolt/Unifying/Lightspeed receivers, Bluetooth, and USB.
    '';
    homepage = "https://openlogi.org";
    changelog = "https://github.com/AprilNEA/OpenLogi/releases/tag/v${version}";
    license = with lib.licenses; [
      mit
      asl20
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "openlogi";
  };
}
