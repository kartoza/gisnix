# Optional per-host locale overrides, layered on top of the preset locale
# module (software/locale/locale-<code>.nix, chosen by `locale` in the
# host's config.nix). The preset couples three things a traveller often
# wants apart — the clock, the desktop language, and number/date/paper
# formatting. Setting any of the fields below overrides just that one axis
# and leaves the rest of the preset intact; leaving a field unset changes
# nothing.
#
# In the host's config.nix (any subset):
#
#   timeZone     = "Europe/Zurich";   # just the clock — e.g. while travelling
#   language     = "en_GB.UTF-8";     # just the desktop language
#   formatLocale = "pt_PT.UTF-8";     # just dates, money, measurements, paper size
#
# So "English desktop, Portuguese number formatting, Zurich clock" is the
# `pt-en` preset plus `timeZone = "Europe/Zurich";`, and coming home is
# removing that one line. `gisnix locale` writes and clears these for you.
{ hostConfig, lib, ... }:
let
  inherit (lib) mkIf mkForce;
  tz = hostConfig.timeZone or null;
  lang = hostConfig.language or null;
  fmt = hostConfig.formatLocale or null;
  lcKeys = [
    "LC_ADDRESS"
    "LC_IDENTIFICATION"
    "LC_MEASUREMENT"
    "LC_MONETARY"
    "LC_NAME"
    "LC_NUMERIC"
    "LC_PAPER"
    "LC_TELEPHONE"
    "LC_TIME"
  ];
in
{
  time.timeZone = mkIf (tz != null) (mkForce tz);
  i18n.defaultLocale = mkIf (lang != null) (mkForce lang);
  i18n.extraLocaleSettings = mkIf (fmt != null) (
    builtins.listToAttrs (map (k: lib.nameValuePair k (mkForce fmt)) lcKeys)
  );
}
