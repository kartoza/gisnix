{
  description = "gisnix — a reproducible, ZFS-encryption-ready NixOS distribution for GIS workstations, built with Kartoza's kz operator tooling";

  nixConfig = {
    # IFD is required for the QGIS repo inputs.
    allow-import-from-derivation = true;
    bash-prompt = "\\[\\033[1m\\][gisnix-dev]\\[\\033[m\\]\\040\\w >\\040";

    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://cosmic.cachix.org/"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cosmic.cachix.org-1:Dya9IyXD4xdBehWjrkPv6rtxpmMdRel02smYzA85dPE="
    ];

    max-jobs = 16;
    cores = 8;
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Unstable nixpkgs for packages that need latest versions (e.g. COSMIC).
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Default terminal-editor bundle: Tim's timvim Neovim configuration.
    nvf = {
      url = "github:timlinux/timvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix/0.15.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere/1.11.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko/v1.11.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    qgis-master-repo.url = "github:qgis/QGIS/master";
    qgis-latest-repo.url = "github:qgis/QGIS/release-3_44";
    qgis-ltr-repo.url = "github:qgis/QGIS/release-3_40";

    geodiff = {
      url = "github:kartoza/nix-geodiff";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Make sure to add packages to overlays/default.nix too
    nixos-utils.url = "github:timlinux/nixos-utils";
    # Make sure to add packages to overlays/default.nix too
    kartoza-plymouth-theme.url = "github:kartoza/kartoza-plymouth-theme";
    # Make sure to add packages to overlays/default.nix too
    kartoza-grub-themes.url = "github:kartoza/kartoza-grub-themes";

    # Terminal transparency tool
    term2alpha = {
      url = "git+https://git.sr.ht/~zethra/term2alpha";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ZFS backup tool with Bubble Tea TUI
    zfs-backup = {
      url = "github:timlinux/zfs-backup";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # wlgif — Wayland region-to-GIF screen recorder.
    wlgif.url = "github:doprz/wlgif";

    # Baboon - terminal typing practice application
    baboon = {
      url = "github:timlinux/baboon";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Gatus Monitor - system tray app for monitoring Gatus health check endpoints
    gatus-monitor = {
      url = "github:kartoza/gatus-monitor";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home-manager for user-level configuration
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Stylix for system-wide theming
    stylix = {
      url = "github:nix-community/stylix/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Auto-updating Nix package for the Antigravity CLI (agy).
    antigravity-nix.url = "github:jacopone/antigravity-nix";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      ...
    }:
    let
      inherit (self) outputs;

      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      defaultPkgs = nixpkgs.legacyPackages.x86_64-linux;
      nixpkgsFor = forAllSystems (
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = false;
        }
      );

      # Project config
      projectConfig = {
        configRevision = if self ? rev then self.rev else "dirty";
        environmentName = builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile ./environment.txt);
      }
      // (import ./config.nix);

      # Build a NixOS system. `hostPath` defaults to this flake's own
      # ./hosts/<hostname> so gisnix's own example host and any others you
      # add here work with just a name — but a downstream flake (e.g. one
      # that layers its own fleet on top of gisnix) can pass its OWN
      # hostPath, pointing at a host directory that lives in ITS repo
      # instead. That is the whole point of exposing this as `lib.mkHost`:
      # the consuming flake stays tiny — its own hosts/ and users/, plus
      # this one function call — while every bundle, profile and overlay
      # still comes from here.
      mkHost =
        hostname:
        {
          hostPath ? ./hosts + "/${hostname}",
          extraModules ? [ ],
        }:
        let
          hostConfig = import (hostPath + "/config.nix");
        in
        nixpkgs.lib.nixosSystem {
          modules = [
            inputs.disko.nixosModules.disko
            inputs.agenix.nixosModules.default
            inputs.home-manager.nixosModules.home-manager
            inputs.stylix.nixosModules.stylix
            hostPath
            # Software bundles: turns hostConfig.bundles into imports. Inert
            # for a host that declares none.
            ./profiles/bundles.nix
            { nixpkgs.overlays = import ./overlays { inherit inputs; }; }
          ]
          ++ extraModules
          ++ nixpkgs.lib.optional (projectConfig.environmentName == "dev") (
            nixpkgs.lib.warn ''
              ------------------------------------------------
              ⚠️  Using insecure development configuration! 🚧
              ------------------------------------------------'' ./profiles/development.nix
          );
          specialArgs = {
            inherit
              inputs
              outputs
              hostname
              hostPath
              projectConfig
              hostConfig
              fleet
              ;
            qgis-master-repo = inputs.qgis-master-repo;
            qgis-latest-repo = inputs.qgis-latest-repo;
            qgis-ltr-repo = inputs.qgis-ltr-repo;
            geodiff = inputs.geodiff;
            kartoza-plymouth-theme = inputs.kartoza-plymouth-theme;
            kartoza-grub-themes = inputs.kartoza-grub-themes;
            nixos-utils = inputs.nixos-utils.packages.x86_64-linux;
            pkgs-unstable = import inputs.nixpkgs-unstable {
              system = "x86_64-linux";
              config.allowUnfree = false;
            };
            # This flake's own root, as an absolute path — so a host living
            # in a DOWNSTREAM flake (hostPath pointing outside this repo,
            # e.g. a machine's own tiny flake pinning gisnix as an input)
            # can still reach shared, non-bundle profiles and locale modules
            # with `gisnixRoot + "/profiles/cosmic-desktop.nix"` instead of a
            # `../../` path that would resolve against the WRONG repo. Bundle
            # modules (software/) don't need this — profiles/bundles.nix
            # already imports those relative to gisnixRoot itself. Only
            # things a host's own default.nix imports directly need it.
            gisnixRoot = ./.;
          };
        };

      # The fleet registry: metadata for every machine this flake manages,
      # plus the unmanaged peers it publishes names for. See hosts/fleet.nix.
      fleet = import ./hosts/fleet.nix;
      allHosts = builtins.attrNames fleet.hosts;
      # Hosts that actually have a server.nix — the only ones a `-deploy`
      # app makes sense for (nixos-anywhere/Hetzner deploys). A test-only
      # host like the shipped example has none.
      deployableHosts = builtins.filter (
        h: builtins.pathExists (./hosts + "/${h}/server.nix")
      ) allHosts;

      # Deploy a NixOS host with nixos-anywhere.
      mkHostDeploy = hostname: {
        type = "app";
        program =
          let
            serverConfig = import ./hosts/${hostname}/server.nix;
            postInstallScript = defaultPkgs.callPackage ./deploy/post-install.nix {
              inherit projectConfig hostname;
              pkgs = defaultPkgs;
              lib = nixpkgs.lib;
            };
            script = defaultPkgs.callPackage ./deploy/install.nix {
              inherit inputs projectConfig hostname;
              pkgs = defaultPkgs;
              lib = nixpkgs.lib;
              nixos-anywhere-pkg = inputs.nixos-anywhere.packages.x86_64-linux.nixos-anywhere;
              serverConfig = serverConfig;
              postInstallScript = postInstallScript;
            };
          in
          nixpkgs.lib.getExe script;
        meta = {
          description = "Deploy ${hostname} host using nixos-anywhere";
        };
      };

      # `kz` — the command-manifest-driven operator CLI. See
      # utils/commands.json and utils/README.md for how a row becomes a
      # flake app, a `kz` subcommand, and a dev-shell binary all at once.
      commandManifest = builtins.fromJSON (builtins.readFile ./utils/commands.json);

      commandPresent =
        c:
        builtins.pathExists (./utils + "/${c.file}")
        && builtins.all (f: builtins.pathExists (./utils/lib + "/${f}")) (c.prelude or [ ]);

      mkCommandBanner =
        c:
        if !(c ? sequence) || c.sequence == [ ] then
          ""
        else
          let
            n = builtins.length c.sequence;
            esc = nixpkgs.lib.escapeShellArg;
            line = i: s: "   ${if i == n then "└" else "├"} ${toString i}. ${s}";
            body = nixpkgs.lib.concatStringsSep "\n" (nixpkgs.lib.imap1 line c.sequence);
          in
          ''
            case "''${1:-}" in
              -h | --help | help) : ;;
              *)
                printf '\n\033[1m▶ %s\033[0m — %s\n' ${esc c.name} ${esc c.desc}
                printf '\033[2m  steps this runs:\033[0m\n'
                printf '%s\n\n' ${esc body}
                ;;
            esac
          '';

      mkCommandDrv =
        c:
        let
          app = defaultPkgs.writeShellApplication {
            name = c.name;
            runtimeInputs =
              nixpkgs.lib.optional (c ? pythonDeps) (
                defaultPkgs.python3.withPackages (ps: map (n: ps.${n}) c.pythonDeps)
              )
              ++ map (d: defaultPkgs.${d}) c.deps;
            excludeShellChecks = c.excludeChecks or [ ];
            text =
              mkCommandBanner c
              + nixpkgs.lib.concatMapStrings (f: builtins.readFile (./utils/lib + "/${f}") + "\n") (
                c.prelude or [ ]
              )
              + builtins.readFile (./utils + "/${c.file}");
          };
        in
        app;

      liveCommands = builtins.filter commandPresent commandManifest.commands;
      commandPackages = map mkCommandDrv liveCommands;

      extraAppNames = builtins.concatMap (h: [
        "${h}-vm"
        "${h}-bootvm"
      ]) allHosts
      ++ builtins.concatMap (h: [ "${h}-deploy" ]) deployableHosts;

      pendingCommands = builtins.filter (c: !(commandPresent c)) commandManifest.commands;

      kzScriptFiles = nixpkgs.lib.sort (a: b: a < b) (
        nixpkgs.lib.unique (
          (map (c: "utils/" + c.file) liveCommands)
          ++ nixpkgs.lib.concatMap (c: map (f: "utils/lib/" + f) (c.prelude or [ ])) liveCommands
        )
      );

      kzScriptHash = builtins.hashString "sha256" (
        nixpkgs.lib.concatMapStrings (f: builtins.readFile (./. + "/${f}")) kzScriptFiles
      );

      kzDispatcher = defaultPkgs.writeShellApplication {
        name = "kz";
        runtimeInputs = [
          defaultPkgs.jq
          defaultPkgs.git
          defaultPkgs.ncurses
          defaultPkgs.nix
          defaultPkgs.coreutils
        ];
        text = ''
          set -uo pipefail

          root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
          if [ -n "$root" ]; then cd "$root"; fi

          cmd="''${1:-}"
          [ $# -gt 0 ] && shift

          kz_is_stale() {
            [ -n "$root" ] || return 1
            local live
            live=$(cat ${nixpkgs.lib.concatStringsSep " " kzScriptFiles} 2>/dev/null \
              | sha256sum | cut -d" " -f1) || return 1
            [ "$live" != "${kzScriptHash}" ]
          }

          case "$cmd" in
            "" | -h | --help | help)
              exec bash utils/dev-help.sh
              ;;
            fleet)
              exec bash utils/fleet-status.sh "$@"
              ;;
            --list)
              cat <<'KZ_LIST'
          ${nixpkgs.lib.concatStringsSep "\n" (
            (map (c: c.name) liveCommands) ++ [ "fleet" ] ++ extraAppNames
          )}
          KZ_LIST
              exit 0
              ;;
          ${nixpkgs.lib.concatMapStrings (c: ''
            ${c.name})
                if kz_is_stale; then
                  printf '\033[38;2;240;230;74mkz: utils/ has changed since this shell was entered\033[0m\n' >&2
                  printf '\033[2m  running %s from the working tree instead of the older build\033[0m\n' ${nixpkgs.lib.escapeShellArg c.name} >&2
                  printf '\033[2m  re-enter the dev shell to stop paying for this\033[0m\n' >&2
                  exec nix --extra-experimental-features "nix-command flakes" \
                    run ".#${c.name}" -- "$@"
                fi
                exec ${mkCommandDrv c}/bin/${c.name} "$@"
                ;;
          '') liveCommands}
          ${nixpkgs.lib.concatMapStrings (n: ''
            ${n})
                exec nix --extra-experimental-features "nix-command flakes" run ".#${n}" -- "$@"
                ;;
          '') extraAppNames}
          ${nixpkgs.lib.concatMapStrings (c: ''
            ${c.name})
                printf '\033[38;2;240;230;74mkz: %s is declared but not implemented yet\033[0m\n' ${nixpkgs.lib.escapeShellArg c.name} >&2
                printf '\033[2m  %s\033[0m\n' ${nixpkgs.lib.escapeShellArg c.desc} >&2
                printf '\033[2m  write utils/%s to bring it to life\033[0m\n' ${nixpkgs.lib.escapeShellArg c.file} >&2
                exit 1
                ;;
          '') pendingCommands}
            *)
              if [ -f utils/commands.json ] \
                && jq -e --arg c "$cmd" \
                     'any(.commands[]; .name == $c)' utils/commands.json >/dev/null 2>&1; then
                file=$(jq -r --arg c "$cmd" \
                  '.commands[] | select(.name == $c) | .file' utils/commands.json)
                if [ -f "utils/$file" ]; then
                  printf '\033[2mkz: %s is newer than this shell — building it\033[0m\n' "$cmd" >&2
                  printf '\033[2m  re-enter the dev shell to stop paying for this\033[0m\n' >&2
                  exec nix --extra-experimental-features "nix-command flakes" \
                    run ".#$cmd" -- "$@"
                fi
                printf '\033[38;2;240;230;74mkz: %s is declared but utils/%s does not exist\033[0m\n' \
                  "$cmd" "$file" >&2
                exit 1
              fi
              printf '\033[0;31mkz: unknown command %s\033[0m\n' "$cmd" >&2
              printf '\033[2mrun kz with no arguments for the list\033[0m\n' >&2
              exit 1
              ;;
          esac
        '';
      };

      # The bootable-USB installer. GISNIX_ROOT is baked in as an absolute
      # store path — on the ISO this checkout IS gisnix, so there is no
      # "find it on disk" step to get wrong the way a symlink-based lookup
      # would have. chafa renders the logo on the raw terminal before the
      # Textual app takes it over (see installer/screens/welcome.py for why
      # the logo is not drawn inside a widget).
      installerPython = defaultPkgs.python3.withPackages (ps: [ ps.textual ]);
      installerPackage = defaultPkgs.writeShellApplication {
        name = "gisnix-installer";
        runtimeInputs = [
          installerPython
          defaultPkgs.chafa
          defaultPkgs.mkpasswd
          defaultPkgs.util-linux # lsblk
          defaultPkgs.curl
          defaultPkgs.disko
          defaultPkgs.nixos-install-tools
        ];
        text = ''
          export GISNIX_ROOT="${./.}"
          clear
          chafa --size=48x "$GISNIX_ROOT/resources/kartoza-logo.png" 2>/dev/null || true
          cd "$GISNIX_ROOT"
          exec python3 -m installer "$@"
        '';
      };

      commandApps = builtins.listToAttrs (
        map (
          c:
          nixpkgs.lib.nameValuePair c.name {
            type = "app";
            program = "${mkCommandDrv c}/bin/${c.name}";
            meta.description = c.desc;
          }
        ) liveCommands
      );

      # Make NixOS VM (QEMU) — fast headless config check; QEMU loads the
      # kernel+initrd directly so GRUB is bypassed and Plymouth is hidden.
      mkVm = hostname: {
        type = "app";
        program = "${nixpkgs.lib.getExe self.nixosConfigurations.${hostname}.config.system.build.vm}";
        meta.description = "Run ${hostname} as a lightweight test VM (QEMU, no bootloader, headless)";
      };

      # Make NixOS VM (QEMU) that boots through GRUB with a graphical
      # console — for iterating on the boot experience without rebooting
      # real hardware. See profiles/boot-vm.nix for the vmVariant overrides.
      mkBootVm =
        hostname:
        let
          vmDrv =
            (self.nixosConfigurations.${hostname}.extendModules {
              modules = [ ./profiles/boot-vm.nix ];
            }).config.system.build.vm;
          qcowPath = "/tmp/nixos-bootvm.qcow2";
          wrapped = defaultPkgs.writeShellScriptBin "run-${hostname}-bootvm" ''
            set -eu
            rm -f ${qcowPath}
            exec ${nixpkgs.lib.getExe vmDrv} "$@"
          '';
        in
        {
          type = "app";
          program = "${wrapped}/bin/run-${hostname}-bootvm";
          meta.description = "Boot ${hostname} through GRUB + Plymouth in QEMU (qcow auto-wiped on each run)";
        };

      mkTest =
        hostname:
        let
          prodConfig = projectConfig // {
            environmentName = "prod";
          };
          hostConfig = import ./hosts/${hostname}/config.nix;
        in
        defaultPkgs.testers.runNixOSTest (
          import ./tests/test-${hostname}.nix {
            inherit inputs outputs hostConfig fleet;
            lib = nixpkgs.lib;
            projectConfig = prodConfig;
          }
        );
    in
    {
      # LIB — exposed for downstream flakes that want to build hosts against
      # gisnix's bundles/profiles/overlays without vendoring any of it. See
      # the mkHost comment above for the intended shape of that call.
      lib = {
        inherit
          mkHost
          mkVm
          mkBootVm
          mkTest
          ;
      };

      # HOSTS
      nixosConfigurations = builtins.listToAttrs (
        map (name: {
          inherit name;
          value = mkHost name { };
        }) allHosts
      );

      # APPS
      apps = forAllSystems (
        system:
        nixpkgs.lib.mapAttrs' (n: v: nixpkgs.lib.nameValuePair (n + "-vm") v) (
          nixpkgs.lib.genAttrs allHosts (h: mkVm h)
        )
        //
          nixpkgs.lib.mapAttrs' (n: v: nixpkgs.lib.nameValuePair (n + "-bootvm") v) (
            nixpkgs.lib.genAttrs allHosts (h: mkBootVm h)
          )
        //
          nixpkgs.lib.mapAttrs' (n: v: nixpkgs.lib.nameValuePair (n + "-deploy") v) (
            nixpkgs.lib.genAttrs deployableHosts (h: mkHostDeploy h)
          )
        // {
          # `nix run .#` and `nix run .#kz` are the same dispatcher: with no
          # arguments it prints the cheat-sheet, with a command name it runs
          # that command.
          default = {
            type = "app";
            program = "${kzDispatcher}/bin/kz";
            meta.description = "Operator commands: `kz` for the list, `kz <command>` to run one";
          };
          kz = {
            type = "app";
            program = "${kzDispatcher}/bin/kz";
            meta.description = "Operator commands: `kz` for the list, `kz <command>` to run one";
          };
          installer = {
            type = "app";
            program = "${installerPackage}/bin/gisnix-installer";
            meta.description = "Launch the Kartoza-branded installer wizard (same tool the ISO boots into)";
          };
        }
        // commandApps
      );

      # PACKAGES
      packages = forAllSystems (system: {
        zfs-backup = inputs.zfs-backup.packages.${system}.default;
        default = self.packages.${system}.zfs-backup;

        # The pinned nixos-anywhere, exposed so `kz install` runs exactly
        # the version this flake locks rather than whatever is on PATH.
        nixos-anywhere = inputs.nixos-anywhere.packages.${system}.nixos-anywhere;

        gisnix-installer = installerPackage;
      });

      # CHECKS
      checks = forAllSystems (
        system:
        let
          tests = import ./tests.nix { inherit mkTest; };
        in
        tests
      );

      # SHELLS
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "bearer" ];
          };
        in
        {
          default = import ./utils/develop.nix {
            inherit inputs system pkgs;
            inherit commandPackages kzDispatcher;
          };
        }
      );

      # Consumed by tooling that wants the host list without evaluating
      # every configuration: `nix eval .#all-hosts --json`.
      all-hosts = allHosts;
    };
}
