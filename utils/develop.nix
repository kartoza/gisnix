{
  inputs,
  pkgs,
  # The `kz` dispatcher, built from utils/commands.json by flake.nix. Only
  # this goes on PATH — not the individual commands.
  #
  # An earlier version put all 25 on PATH directly, which was worse than it
  # looked: `update`, `check`, `test`, `env` and `release` are names the base
  # system already claims, so a bare `update` either shadowed something else
  # or was shadowed by it, silently. `kz update` can only mean ours.
  kzDispatcher ? null,
  # Kept so `nix build` and friends can still reach the individual command
  # derivations; not placed on PATH.
  commandPackages ? [ ],
  ...
}:
pkgs.mkShell {
  packages = pkgs.lib.optional (kzDispatcher != null) kzDispatcher ++ [
    # bashInteractive shadows the stdenv's minimal (readline-less) bash on
    # PATH. Without this, typing `bash` inside `nix develop` gives a shell
    # with no line editing, which renders starship's \[ \] prompt markers
    # literally (and drops tab-completion / history).
    pkgs.bashInteractive
    inputs.nvf.packages.${pkgs.stdenv.hostPlatform.system}.default # my own neovim package (fork)
    pkgs.rage # Secrets management
    # Development
    pkgs.gum # UX for TUIs
    pkgs.jq # JSON wrangling

    # Renders the entry banner. This was called by the shellHook but never
    # declared, so it only worked on machines that happened to have chafa
    # installed system-wide — and because the call swallowed its own stderr,
    # a machine without it simply showed no banner and said nothing.
    pkgs.chafa

    # `tput cols`, used to size the banner when COLUMNS is not exported.
    # Guarded with a fallback, so its absence was silent rather than broken —
    # but an 80-column guess on a wide terminal looks like a bug.
    pkgs.ncurses

    pkgs.gource # Software version control visualization
    pkgs.ffmpeg # Convert gource videos to gifs
    pkgs.pre-commit # for formatting commits
    pkgs.nixfmt-rfc-style # formatting compliance with nix standards
    pkgs.bearer
    pkgs.shfmt
    pkgs.markdownlint-cli
    pkgs.actionlint
    pkgs.shellcheck
    pkgs.cspell
    # Deployment
    pkgs.hcloud
    pkgs.catimg # For generating banners for the alpha neovim start banner
    inputs.term2alpha.packages.${pkgs.stdenv.hostPlatform.system}.default # used with the catimg app to make alpha splash
    # Hardware detection utilities
    pkgs.pciutils # provides lspci
    pkgs.usbutils # provides lsusb
    pkgs.dmidecode # provides dmidecode

    # Docs site: mkdocs-material and the python interpreter used by
    # docs/scripts/generate-host-docs.py. Mirrors flake.nix:docsPython so `nix
    # develop` and `nix run .#docs-*` agree on versions.
    # mkdocs + plugins for the docs site. mkdocs-with-pdf is NOT included
    # here (it's not in nixpkgs on this channel; the flake builds it via
    # buildPythonPackage for the `nix run .#docs-pdf` app instead). The
    # dev shell stays small; for PDF work use the flake app directly.
    (pkgs.python3.withPackages (
      ps: with ps; [
        mkdocs
        mkdocs-material
        mkdocs-glightbox
        mkdocs-git-revision-date-localized-plugin
        pymdown-extensions
        pygments
        # textual: so `GISNIX_INSTALLER_MOCK=1 python3 -m installer` (or
        # `python3 -m installer --mock`) runs straight from the working
        # tree — no `nix run`/rebuild between edits, the fastest loop for
        # iterating on the installer wizard's screens.
        textual
      ]
    ))
  ];

  shellHook = ''
    # Repo root, so `kz` and the banner find utils/ from any subdirectory.
    export NIX_CONFIG_ROOT="$PWD"

    # Point glibc at a locale archive so en_GB.UTF-8 (and friends) resolve
    # inside the dev shell — otherwise bash warns "cannot change locale".
    export LOCALE_ARCHIVE="${pkgs.glibcLocales}/lib/locale/locale-archive"

    # The banner itself lives in utils/shell-banner.sh, not inline here. It is
    # forty lines of shell, this project's rule is not to embed code in nix
    # files, and — the reason it matters — direnv captures the shellHook's
    # output, so anyone entering through direnv never saw it. .envrc calls the
    # same script directly.
    clear
    bash "$NIX_CONFIG_ROOT/utils/shell-banner.sh" || true
  '';
}
