{
  config,
  pkgs,
  ...
}:
let
  # Define the TTF font to be used (e.g., Hack Nerd Font)
  fontHack = pkgs.nerd-fonts.hack;
  ttfFontPath = "${fontHack}/share/fonts/truetype/HackNerdFontMono-Regular.ttf";
in
{

  # This is one of two approaches to get better TTY fonts and Unicode support.
  # This approach uses kmscon, which is more stable than fbterm,
  # especially with systemd, but requires a KMS-compatible graphics setup.
  # The other approach is to use fbterm (see tty-fonts-fbterm.nix).

  imports = [ ./tty-fonts-common.nix ];

  # Ensure kmscon and the font are included in the system packages
  environment.systemPackages = with pkgs; [
    kmscon
    fontHack
  ];
  # Note: vt.default_red/grn/blu are generated automatically by NixOS
  # from console.colors (set in tty-fonts-common.nix).  Do NOT add a
  # second copy here as `boot.kernelParams` — the kernel command line
  # would then contain two `vt.default_red=...` entries and the second
  # one would supersede the first with unexpected values, or, if any
  # other module also drives console.colors (e.g. Stylix), the two
  # lists concatenate and blow past the kernel's 16-argument limit.

  # Enable and configure kmscon service

  services.kmscon = {
    enable = true;
    # Kartoza brand color palette for kmscon
    # Colors derived from Kartoza brand: highlight1=#DF9E2F, highlight2=#569FC6,
    # highlight3=#8A8B8B, highlight4=#06969A, alert=#CC0403
    extraConfig = ''
      sb-size=10240
      font-size=24
      no-drm
      no-switchvt
      grab-scroll-up=
      grab-scroll-down=
      palette=custom
      palette-black=31,31,31
      palette-red=193,48,34
      palette-green=6,150,154
      palette-yellow=235,177,68
      palette-blue=86,159,198
      palette-magenta=122,29,21
      palette-cyan=239,235,234
      palette-light-grey=209,206,206
      palette-dark-grey=138,139,139
      palette-light-red=240,182,67
      palette-light-green=236,180,75
      palette-light-yellow=240,236,235
      palette-light-blue=239,234,233
      palette-light-magenta=238,234,233
      palette-light-cyan=253,252,252
      palette-white=241,238,237
      palette-foreground=235,177,68
      palette-background=31,31,31
    '';
    useXkbConfig = true;
    hwRender = false;
    extraOptions = "--term=xterm-256color --no-reset"; # Pass extra command-line options to kmscon
    fonts = [
      {
        name = "FiraCode Nerd Font Mono";
        package = pkgs.nerd-fonts.fira-mono;
      }
    ];
  };

}
