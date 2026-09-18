# India — English working locale.
#
# India has a single time zone (Asia/Kolkata, IST, UTC+05:30, no DST) but many
# languages. Bhaskar works in English, so this pairs en_IN with Indian
# regional conventions: dd/mm/yyyy dates, the rupee, and Indian digit grouping
# (1,00,000 rather than 100,000).
#
# Deliberately NOT copied from locale-za-en.nix / locale-ke-en.nix: those both
# set console.keyMap = "pt-latin1" (Portuguese) and install aspellDicts.uk,
# which is Ukrainian, not British English. Both look like copy-paste from the
# Portugal module.
{ pkgs, ... }:
{
  # `en_IN`, NOT `en_IN.UTF-8`. glibc's SUPPORTED list spells this one
  # `en_IN/UTF-8` — the locale name carries no charset suffix, unlike
  # `en_ZA.UTF-8/UTF-8` or `en_GB.UTF-8/UTF-8`. NixOS appends `/UTF-8` when
  # it builds supportedLocales, so `en_IN` produces the right entry and
  # `en_IN.UTF-8` produces one glibc rejects:
  #
  #   Error: unsupported locales detected: en_IN.UTF-8/UTF-8
  #
  # which fails the glibc-locales build, and therefore any build of bay —
  # the only host taking this locale.
  time.timeZone = "Asia/Kolkata";

  i18n.defaultLocale = "en_IN";

  # en_IN covers dates, money, paper and number formatting. Messages stay
  # English because en_IN *is* English.
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_IN";
    LC_IDENTIFICATION = "en_IN";
    LC_MEASUREMENT = "en_IN";
    LC_MONETARY = "en_IN";
    LC_NAME = "en_IN";
    LC_NUMERIC = "en_IN";
    LC_PAPER = "en_IN";
    LC_TELEPHONE = "en_IN";
    LC_TIME = "en_IN";
  };

  # Indian keyboards are physically US layout; the "in" xkb layout is for
  # Indic script input, which is not wanted for English work.
  services.xserver = {
    xkb.layout = "us";
    xkb.variant = "";
  };

  console.keyMap = "us";

  environment.systemPackages = with pkgs; [
    aspell
    aspellDicts.en
  ];
}
