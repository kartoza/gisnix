{
  description = "gisnix — a reproducible, ZFS-encryption-ready NixOS distribution for GIS workstations, built with Kartoza's gisnix operator tooling";

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

    # QGIS's own repo (for the opt-in desktop-gis-source-builds bundle) is
    # deliberately NOT a flake input here — every input in this block gets
    # fetched (recursively, including ITS OWN sub-inputs) on any flake
    # evaluation, including a bare `nix develop` that never touches that
    # bundle. software/desktop/gis/source-builds/*.nix fetch it lazily via
    # `builtins.getFlake` on a pinned rev instead — see qgis-dev.nix.

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
          # See overlays/default.nix's own comment — this exists for the
          # installer's first-boot flake only. Everything else should leave
          # it alone and get COSMIC from nixpkgs-unstable as usual.
          stableCosmic ? false,
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
            { nixpkgs.overlays = import ./overlays { inherit inputs stableCosmic; }; }
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

      # `gisnix` — the command-manifest-driven operator CLI. See
      # utils/commands.json and utils/README.md for how a row becomes a
      # flake app, a `gisnix` subcommand, and a dev-shell binary all at once.
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

      extraAppNames = [
        "docs-serve"
        "docs-build"
        "docs-generate-bundles"
        "docs-generate-commands"
        "docs-generate-hosts"
        "docs-generate-software"
        "test-install"
        "test-boot"
      ]
      ++ builtins.concatMap (h: [
        "${h}-vm"
        "${h}-bootvm"
      ]) allHosts
      ++ builtins.concatMap (h: [ "${h}-deploy" ]) deployableHosts;

      # Docs site: mkdocs-material and the interpreter used by
      # docs/scripts/generate-*.py. Not part of the commands.json manifest
      # (same as nix-config's own docs apps) — these interpolate a python
      # environment and store paths that don't fit the manifest's plain
      # deps/pythonDeps shape as cleanly; `gisnix docs-serve` etc. still reach
      # them, via extraAppNames rather than a commandApps row.
      docsPython = defaultPkgs.python3.withPackages (
        ps: with ps; [
          mkdocs
          mkdocs-material
          mkdocs-glightbox
          mkdocs-git-revision-date-localized-plugin
          pymdown-extensions
          pygments
        ]
      );

      # Both generated reference pages, refreshed before anything renders
      # the site — without this, docs-serve/docs-build show whatever was
      # last committed.
      regenerateDocs = ''
        echo "Regenerating bundle reference..."
        python3 docs/scripts/generate-bundle-docs.py
        echo "Regenerating command reference..."
        python3 docs/scripts/generate-commands-docs.py
      '';

      mkDocsApp =
        {
          name,
          description,
          body,
          extraInputs ? [ ],
        }:
        {
          type = "app";
          program = "${
            defaultPkgs.writeShellApplication {
              inherit name;
              runtimeInputs = [
                docsPython
                defaultPkgs.git
              ]
              ++ extraInputs;
              text = ''
                cd "$(git rev-parse --show-toplevel)"
                ${body}
              '';
            }
          }/bin/${name}";
          meta.description = description;
        };

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

      gisnixDispatcher = defaultPkgs.writeShellApplication {
        name = "gisnix";
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

          gisnix_is_stale() {
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
              cat <<'GISNIX_LIST'
          ${nixpkgs.lib.concatStringsSep "\n" (
            (map (c: c.name) liveCommands) ++ [ "fleet" ] ++ extraAppNames
          )}
          GISNIX_LIST
              exit 0
              ;;
          ${nixpkgs.lib.concatMapStrings (c: ''
            ${c.name})
                if gisnix_is_stale; then
                  printf '\033[38;2;240;230;74mgisnix: utils/ has changed since this shell was entered\033[0m\n' >&2
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
                printf '\033[38;2;240;230;74mgisnix: %s is declared but not implemented yet\033[0m\n' ${nixpkgs.lib.escapeShellArg c.name} >&2
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
                  printf '\033[2mgisnix: %s is newer than this shell — building it\033[0m\n' "$cmd" >&2
                  printf '\033[2m  re-enter the dev shell to stop paying for this\033[0m\n' >&2
                  exec nix --extra-experimental-features "nix-command flakes" \
                    run ".#$cmd" -- "$@"
                fi
                printf '\033[38;2;240;230;74mgisnix: %s is declared but utils/%s does not exist\033[0m\n' \
                  "$cmd" "$file" >&2
                exit 1
              fi
              printf '\033[0;31mgisnix: unknown command %s\033[0m\n' "$cmd" >&2
              printf '\033[2mrun gisnix with no arguments for the list\033[0m\n' >&2
              exit 1
              ;;
          esac
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
      nixosConfigurations =
        builtins.listToAttrs (
          map (name: {
            inherit name;
            value = mkHost name { };
          }) allHosts
        )
        // {
          # The installer ISO — x86_64 only for now. Not built through
          # mkHost: it isn't a fleet host, it's the thing that CREATES one.
          installer = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = {
              gisnixSetup = self.packages.x86_64-linux.gisnix-setup;
            };
            modules = [ ./installer.nix ];
          };
        };

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
          # `nix run .#` and `nix run .#gisnix` are the same dispatcher: with
          # no arguments it prints the cheat-sheet, with a command name it
          # runs that command.
          default = {
            type = "app";
            program = "${gisnixDispatcher}/bin/gisnix";
            meta.description = "Operator commands: `gisnix` for the list, `gisnix <command>` to run one";
          };
          gisnix = {
            type = "app";
            program = "${gisnixDispatcher}/bin/gisnix";
            meta.description = "Operator commands: `gisnix` for the list, `gisnix <command>` to run one";
          };
          # Build the installer ISO and boot it in QEMU — the fastest way to
          # try the real (non-mock) `setup` wizard against a real virtual disk,
          # UEFI, and TTY. Persists the test disk (tuinix-style) across runs
          # so a completed install survives a reboot for inspection; delete
          # gisnix-test.qcow2 to start over.
          test-install = {
            type = "app";
            program = toString (
              defaultPkgs.writeShellScript "test-install" ''
                set -e
                echo "Building installer ISO..."
                nix build .#nixosConfigurations.installer.config.system.build.isoImage --print-build-logs
                ISO=$(find result/iso -name "*.iso" | head -1)
                if [ -z "$ISO" ]; then
                  echo "ERROR: No ISO found in result/iso/" >&2
                  exit 1
                fi
                echo "ISO built: $ISO"

                DISK="gisnix-test.qcow2"
                if [ ! -f "$DISK" ]; then
                  echo "Creating 40G test disk..."
                  ${defaultPkgs.qemu}/bin/qemu-img create -f qcow2 "$DISK" 40G
                fi

                OVMF_CODE="${defaultPkgs.OVMF.fd}/FV/OVMF_CODE.fd"
                OVMF_VARS_SRC="${defaultPkgs.OVMF.fd}/FV/OVMF_VARS.fd"
                OVMF_VARS="$PWD/.gisnix-test-OVMF_VARS.fd"
                cp -f "$OVMF_VARS_SRC" "$OVMF_VARS"
                chmod 600 "$OVMF_VARS"

                echo "Launching QEMU..."
                ${defaultPkgs.qemu}/bin/qemu-system-x86_64 \
                  -enable-kvm \
                  -m 8G \
                  -smp 4 \
                  -cpu host \
                  -machine q35,accel=kvm \
                  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
                  -drive if=pflash,format=raw,file="$OVMF_VARS" \
                  -drive file="$DISK",format=qcow2,if=none,id=disk0 \
                  -device virtio-blk-pci,drive=disk0,serial=gisnix-root \
                  -cdrom "$ISO" \
                  -boot order=dc,menu=on \
                  -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::2223-:2222 \
                  -device virtio-net-pci,netdev=net0 \
                  -display sdl \
                  -usb -device qemu-xhci -device usb-tablet \
                  -name "gisnix installer test"
              ''
            );
            meta.description = "Build the installer ISO and boot it in QEMU with a persistent 40G test disk";
          };
          # Same QEMU launch as test-install, but skips `nix build` entirely
          # when result/iso already has one — for relaunching after closing
          # the window by mistake, or any other case where the ISO you
          # already have is the one you want. Note this means it's also the
          # WRONG command right after changing anything that affects the
          # ISO's own closure (installer/*.py, or a bundle the live ISO
          # imports) — those changes won't be in an ISO built before them,
          # and this command has no way to tell the two cases apart. Use
          # test-install itself when in doubt.
          test-boot = {
            type = "app";
            program = toString (
              defaultPkgs.writeShellScript "test-boot" ''
                set -e
                ISO=$(find result/iso -name "*.iso" 2>/dev/null | head -1)
                if [ -z "$ISO" ]; then
                  echo "No ISO in result/iso/ yet — building it first..."
                  nix build .#nixosConfigurations.installer.config.system.build.isoImage --print-build-logs
                  ISO=$(find result/iso -name "*.iso" | head -1)
                  if [ -z "$ISO" ]; then
                    echo "ERROR: No ISO found in result/iso/ even after building" >&2
                    exit 1
                  fi
                fi
                echo "Using ISO: $ISO"

                DISK="gisnix-test.qcow2"
                if [ ! -f "$DISK" ]; then
                  echo "ERROR: $DISK not found — nothing to boot yet. Run test-install first." >&2
                  exit 1
                fi

                OVMF_CODE="${defaultPkgs.OVMF.fd}/FV/OVMF_CODE.fd"
                OVMF_VARS="$PWD/.gisnix-test-OVMF_VARS.fd"
                if [ ! -f "$OVMF_VARS" ]; then
                  echo "ERROR: $OVMF_VARS not found — run test-install first to set up UEFI vars." >&2
                  exit 1
                fi

                echo "Launching QEMU..."
                ${defaultPkgs.qemu}/bin/qemu-system-x86_64 \
                  -enable-kvm \
                  -m 8G \
                  -smp 4 \
                  -cpu host \
                  -machine q35,accel=kvm \
                  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
                  -drive if=pflash,format=raw,file="$OVMF_VARS" \
                  -drive file="$DISK",format=qcow2,if=none,id=disk0 \
                  -device virtio-blk-pci,drive=disk0,serial=gisnix-root \
                  -cdrom "$ISO" \
                  -boot order=dc,menu=on \
                  -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::2223-:2222 \
                  -device virtio-net-pci,netdev=net0 \
                  -display sdl \
                  -usb -device qemu-xhci -device usb-tablet \
                  -name "gisnix installer test"
              ''
            );
            meta.description = "Relaunch the existing test ISO/disk in QEMU without rebuilding (only builds if result/iso is empty)";
          };
          docs-serve = mkDocsApp {
            name = "docs-serve";
            description = "Serve the docs site locally with live reload (opens a browser)";
            extraInputs = [
              defaultPkgs.xdg-utils
              defaultPkgs.coreutils
            ];
            body = ''
              ${regenerateDocs}
              (
                for _ in $(seq 1 30); do
                  if (exec 3<>/dev/tcp/127.0.0.1/8000) 2>/dev/null; then
                    exec 3>&- 3<&-
                    xdg-open http://127.0.0.1:8000/ >/dev/null 2>&1 || true
                    break
                  fi
                  sleep 0.5
                done
              ) &
              exec mkdocs serve "$@"
            '';
          };
          docs-build = mkDocsApp {
            name = "docs-build";
            description = "Build the static docs site (mkdocs build --strict)";
            body = ''
              ${regenerateDocs}
              exec mkdocs build --strict "$@"
            '';
          };
          docs-generate-bundles = mkDocsApp {
            name = "docs-generate-bundles";
            description = "Regenerate docs/references/bundles.md from the bundle definitions";
            body = "exec python3 docs/scripts/generate-bundle-docs.py";
          };
          docs-generate-commands = mkDocsApp {
            name = "docs-generate-commands";
            description = "Regenerate docs/references/commands.md from utils/commands.json";
            body = "exec python3 docs/scripts/generate-commands-docs.py";
          };
          # Both of these run `nix eval` against every host in .#all-hosts,
          # so — unlike the two above — they need a real nix daemon and a
          # full flake evaluation. Not runnable in a sandboxed agent
          # environment without one; that's also exactly why nobody had
          # verified they still worked against gisnix's own example host
          # until they were finally wired up here.
          docs-generate-hosts = mkDocsApp {
            name = "docs-generate-hosts";
            description = "Regenerate docs/hosts/<host>.md from each host's evaluated config";
            extraInputs = [ defaultPkgs.nix ];
            body = "exec python3 docs/scripts/generate-host-docs.py";
          };
          docs-generate-software = mkDocsApp {
            name = "docs-generate-software";
            description = "Regenerate docs/references/software.md, the fleet-wide package catalogue";
            extraInputs = [ defaultPkgs.nix ];
            body = "exec python3 docs/scripts/generate-software-catalogue.py";
          };
        }
        // commandApps
      );

      # PACKAGES
      packages = forAllSystems (system: {
        zfs-backup = inputs.zfs-backup.packages.${system}.default;
        default = self.packages.${system}.zfs-backup;

        # The pinned nixos-anywhere, exposed so `gisnix install` runs exactly
        # the version this flake locks rather than whatever is on PATH.
        nixos-anywhere = inputs.nixos-anywhere.packages.${system}.nixos-anywhere;

        # The setup wizard, as a standalone package (not just a `gisnix`
        # subcommand) — this is what the ISO's environment.systemPackages
        # installs. Built from the SAME manifest row as `gisnix setup`/
        # `nix run .#setup`, so there is exactly one definition of what the
        # wizard needs.
        gisnix-setup = mkCommandDrv (
          builtins.head (builtins.filter (c: c.name == "setup") commandManifest.commands)
        );
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
            inherit inputs system pkgs commandPackages gisnixDispatcher;
          };
        }
      );

      # Consumed by tooling that wants the host list without evaluating
      # every configuration: `nix eval .#all-hosts --json`.
      all-hosts = allHosts;
    };
}
