# Vendored from nixpkgs (pkgs/by-name/ba/bazecor/package.nix) and bumped from
# the 1.9.0 that nixos-unstable currently pins to 1.9.2. Newer Dygma firmware
# (and the Defy handled here) needs Bazecor >= 1.9.1 to be recognised, so we
# carry this local derivation until nixpkgs ships >= 1.9.2. When that lands,
# delete overlays/pkgs/bazecor and drop the overlay entry, reverting to the
# upstream package.
#
# Upstream reference:
# https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/ba/bazecor/package.nix
{
  lib,
  appimageTools,
  fetchurl,
  makeWrapper,
}:
let
  pname = "bazecor";
  version = "1.9.2";
  src = appimageTools.extract {
    inherit pname version;
    src = fetchurl {
      url = "https://github.com/Dygmalab/Bazecor/releases/download/v${version}/Bazecor-${version}-x64.AppImage";
      hash = "sha256-9em1S7/+2cWJYqOESgGV/kJHlk+a7AOahyibN3NDJv8=";
    };

    # Workaround for https://github.com/Dygmalab/Bazecor/issues/370 — force the
    # in-app udev self-check to pass. The minified bundle string can shift
    # between releases, so use --replace-warn (not --replace-fail): if the
    # pattern moves we still get a working build that relies on the real udev
    # rules installed below, just without the cosmetic short-circuit.
    postExtract = ''
      substituteInPlace \
        $out/usr/lib/bazecor/resources/app/.webpack/main/index.js \
        --replace-warn \
          'checkUdev=()=>{try{if(l.default.existsSync(h))return l.default.readFileSync(h,"utf-8").trim()===f.trim()}catch(e){d.default.error(e)}return!1}' \
          'checkUdev=()=>{return 1}'
    '';
  };
in
appimageTools.wrapAppImage {
  inherit pname version src;

  # also make sure to update the udev rules in ./60-dygma.rules; most recently
  # taken from
  # https://github.com/Dygmalab/Bazecor/blob/v1.4.4/src/main/utils/udev.ts#L6

  nativeBuildInputs = [ makeWrapper ];

  extraPkgs = pkgs: [ pkgs.glib ];

  # Also expose the udev rules here, so it can be used as:
  #   services.udev.packages = [ pkgs.bazecor ];
  # to allow non-root modifications to the keyboards.

  extraInstallCommands = ''
    wrapProgram $out/bin/bazecor \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"

    install -m 444 -D ${src}/Bazecor.desktop -t $out/share/applications
    install -m 444 -D ${src}/bazecor.png -t $out/share/icons/hicolor/512x512/apps

    mkdir -p $out/lib/udev/rules.d
    install -m 444 -D ${./60-dygma.rules} $out/lib/udev/rules.d/60-dygma.rules

    substituteInPlace $out/share/applications/Bazecor.desktop \
      --replace-fail 'Exec=Bazecor' 'Exec=bazecor'
  '';

  meta = {
    description = "Graphical configurator for Dygma Products";
    homepage = "https://github.com/Dygmalab/Bazecor";
    changelog = "https://github.com/Dygmalab/Bazecor/releases/tag/v${version}";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [
      gcleroux
    ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "bazecor";
  };
}
