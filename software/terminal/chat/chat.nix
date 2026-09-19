# Terminal chat and forum clients — full-screen apps for talking to people
# without leaving the terminal, distinct from mail.nix (aerc, which lives
# in the sibling terminal-tuis bundle instead). Its OWN bundle
# (terminal-chat, a sibling of terminal-tuis — see ./bundle.json) rather
# than a file folded inside terminal-tuis: that first placement made it
# a module of a bundle nearly every host already takes, and a taxonomy
# group people can't select independently isn't really a group. This is
# also the home for the next one of these (IRC TUIs and the like).
#
# OPT-IN AT THE BUNDLE LEVEL, same enableAll + apps.<id>.enable shape as
# kartoza-webapps.nix — but enableAll DEFAULTS TO TRUE, also matching
# kartoza-webapps.nix, not the mkEnableOption-default false a first
# version of this file used. That version installed all four
# unconditionally regardless of any option (fixed by gating on options
# at all), then defaulted enableAll to false too (fixed here): the
# result was a bundle that, taken through gisnix configure exactly as
# intended, installed nothing — gisnix configure adds bundles, it does not
# reach into a module's own options, so there was no second step it
# could have walked anyone through. Once terminal-chat became its own
# deliberately-selectable bundle (a host has to name it on purpose),
# "taken the bundle" is exactly the intent "enableAll = true" should
# read as — the same bar every other bundle in the fleet already
# installs at. Opt OUT of one app while keeping the rest:
#
#   programs.terminal-chat.enableAll = false;
#   programs.terminal-chat.apps.tut.enable = true;      # just this one
#
# perch and siggy are GPL-3.0-or-later / AGPL-3.0-only respectively —
# approved 2026-09-16 (see overlays/pkgs/{perch,siggy}/package.nix).
#
# `config` below spells out one `lib.optionals cond [ pkgs.foo ]` per app,
# each package written as its own bracketed literal, rather than the
# shorter `lib.concatMap (appDef: appDef.packages) (lib.attrValues
# enabledApps)` an attrset-driven version would use. `gisnix configure`'s
# package pane (utils/lib/bundleinfo.py:packages_in) reads modules by
# TEXT, not evaluation — it looks for a literal `[ … ]` sitting directly
# in an `environment.systemPackages = …` statement, so a dynamically
# assembled list is invisible to it (reported "no package list in this
# module", not "installs nothing" — the distinction the tool itself
# draws). A first version of this file hit exactly that; this shape
# keeps every package name visible to the one tool that inventories them.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.terminal-chat;

  # Descriptions only, for the mkEnableOption text — the packages
  # themselves are NOT looked up through this attrset (see the config
  # block: each app's bracket is written out literally there instead,
  # for gisnix configure's sake).
  apps = {
    discourse-tui.description = "Browse/reply to Discourse forums";
    tut.description = "Mastodon TUI, vim-style keys";
    perch.description = "Mastodon + Bluesky TUI";
    siggy.description = "Signal TUI, wraps signal-cli (device-link with `siggy --setup`)";
  };

  enabled = appId: cfg.enableAll || cfg.apps.${appId}.enable;
in
{
  options.programs.terminal-chat = {
    # mkEnableOption defaults to false; overridden to true here so that
    # taking the terminal-chat BUNDLE (the actual point of it being its
    # own bundle now) installs its apps, matching kartoza-webapps.nix and
    # every other bundle in the fleet. See the header comment.
    enableAll =
      lib.mkEnableOption "all terminal chat/forum clients (discourse-tui, tut, perch, siggy)"
      // {
        default = true;
      };

    apps = lib.mkOption {
      type = lib.types.submodule {
        options = builtins.mapAttrs (
          appId: appDef:
          lib.mkOption {
            type = lib.types.submodule {
              options = {
                enable = lib.mkEnableOption "${appId} — ${appDef.description}";
              };
            };
            default = { };
          }
        ) apps;
      };
      default = { };
      description = "Terminal chat/forum clients to enable individually.";
    };
  };

  config = lib.mkIf (builtins.any enabled (builtins.attrNames apps)) {
    environment.systemPackages =
      lib.optionals (enabled "discourse-tui") [ pkgs.discourse-tui ]
      ++ lib.optionals (enabled "tut") [ pkgs.tut ]
      ++ lib.optionals (enabled "perch") [ pkgs.perch ]
      # signal-cli is siggy's runtime backend (JSON-RPC), not a
      # selectable app of its own — it rides along with siggy rather
      # than getting its own toggle.
      ++ lib.optionals (enabled "siggy") [
        pkgs.siggy
        pkgs.signal-cli
      ];
  };
}
