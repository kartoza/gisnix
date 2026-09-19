# Where the kanata email macro gets its data — see kanata-config.nix's
# `emailScript` and docs/user/keyboard.md's herdr-layer section. kanata's
# config is baked at build time, but which user is logged in is a runtime
# fact, so "whose email is this" is resolved by a script kanata runs at
# PRESS time (loginctl -> username -> the address that user declared here),
# not by anything in the Nix config itself.
#
# Each user states their own address in their OWN file:
#
#   # users/tim.nix
#   kartoza.userEmails.tim = "tim@example.com";
#
# No user has declared one by default, so the generated script's case
# statement is empty and every press refuses (prints the empty list) —
# the mechanism ships inert until a user opts themselves in by stating
# their address, rather than typing nothing useful for everyone else.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  emailCases = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: email: ''    ${name}) email="${email}" ;;''
    ) config.kartoza.userEmails
  );

  # REFUSE RATHER THAN GUESS: only characters that are either layout-
  # independent (a-z, 0-9, .) or explicitly mapped per layout (@, -) become
  # keycodes. A silently wrong keycode would type a plausible address that
  # is not yours, and nobody proofreads an email field their keyboard filled
  # in — so an unmapped character, or no email declared for the active
  # user, prints the empty list `()` and the key goes quiet instead.
  script = pkgs.writeShellScript "kanata-type-email" ''
    set -euo pipefail
    layout="''${1:-us}"

    refuse() { echo "()"; exit 0; }

    sid=$(loginctl show-seat seat0 --property=ActiveSession --value 2>/dev/null) || refuse
    [ -n "$sid" ] || refuse
    user=$(loginctl show-session "$sid" --property=Name --value 2>/dev/null) || refuse
    [ -n "$user" ] || refuse

    case "$user" in
${emailCases}
      *) refuse ;;
    esac

    keys=()
    for ((i = 0; i < ''${#email}; i++)); do
      ch=''${email:i:1}
      case "$ch" in
        [a-z0-9.]) keys+=("$ch") ;;
        @)
          if [ "$layout" = "pt" ]; then
            keys+=("AG-2")
          else
            keys+=("S-2")
          fi
          ;;
        -)
          if [ "$layout" = "pt" ]; then
            keys+=("/")
          else
            keys+=("min")
          fi
          ;;
        *) refuse ;;
      esac
    done

    echo "(''${keys[*]})"
  '';
in
{
  options.kartoza.userEmails = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    example = {
      tim = "tim@example.com";
    };
    description = ''
      Map of Linux username -> email address, typed by the herdr layer's
      `e` key (hold Caps Lock — see docs/user/keyboard.md). Set an entry
      from the user's OWN file (`kartoza.userEmails.<name> = "...";` in
      `users/<name>.nix`), not centrally — each user owns their own
      address. Resolved at press time against whoever the active session
      actually is, so the same physical key types the right address under
      each account on a shared machine. A username with no entry here
      leaves the macro silent for them; nothing else about their account
      changes.
    '';
  };

  options.kartoza.kanataEmailScript = lib.mkOption {
    type = lib.types.nullOr lib.types.package;
    default = null;
    internal = true;
    description = ''
      Generated kanata-type-email script, or null if `kartoza.userEmails`
      is empty. Set automatically — not meant to be set by hand.
    '';
  };

  config.kartoza.kanataEmailScript = lib.mkIf (config.kartoza.userEmails != { }) script;
}
