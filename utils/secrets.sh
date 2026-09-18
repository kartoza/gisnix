#!/usr/bin/env bash
#
# secrets — what is encrypted, and who can decrypt it.
#
# Read-only. It does not decrypt anything: it reports the shape of
# secrets/secrets.nix and the age recipients on each file, so you can answer
# "can this host read that secret?" without reaching for a passphrase.
#
#   kz secrets            (or: kz secrets)
#   kz secrets --recipients      show every recipient key in full
#
# agenix encrypts each .age file to a list of public keys declared in
# secrets/secrets.nix. Adding a host or a person means adding their key there
# and re-encrypting — `kz provision-secrets` does that part.
set -uo pipefail

GREEN=$'\033[38;2;88;150;50m'
YELLOW=$'\033[38;2;240;230;74m'
RED=$'\033[0;31m'
BLUE=$'\033[38;2;147;176;35m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
NC=$'\033[0m'

SHOW_KEYS=0
case "${1:-}" in
  --recipients) SHOW_KEYS=1 ;;
  -h | --help)
    awk 'NR>1 && /^# shellcheck/ {next} NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
    exit 0
    ;;
  "") ;;
  *)
    echo "${RED}unknown argument: $1${NC}" >&2
    exit 1
    ;;
esac

[ -f secrets/secrets.nix ] || {
  echo "${RED}✗ run from the repo root (secrets/secrets.nix missing)${NC}"
  exit 1
}

NIX=(nix --extra-experimental-features 'nix-command flakes')

# Recipients are read from the .age headers, not from secrets/secrets.nix.
#
# That file cannot be imported on its own: it derives its recipient lists from
# users/default.nix, which needs a real module `config` and `pkgs` to evaluate.
# Reading the headers is better anyway — secrets.nix says who SHOULD be able to
# decrypt a file, the header says who actually can, and it is the gap between
# the two that causes "host X cannot read secret Y after I added it".
#
# An age header is plain text before the payload: one `-> <type> <args>` stanza
# per recipient. Counting them needs no key and decrypts nothing.
#
# Grease stanzas are filtered out. age deliberately emits stanzas with random
# labels as padding, so that implementations cannot come to depend on the exact
# header shape. Counting those as readers overstated this file by one.
recipients_of() { # <file>
  head -c 8192 "$1" 2> /dev/null |
    LC_ALL=C grep -aoE '^-> (ssh-ed25519|ssh-rsa|X25519|scrypt)' |
    sed 's/^-> //'
}

echo
echo "${BOLD}Encrypted secrets${NC}  ${DIM}secrets/${NC}"
echo "${DIM}──────────────────────────────────────────────────────────────────────${NC}"

# Declared names come from secrets.nix. Only the attribute names are needed,
# and those evaluate fine — it is the publicKeys lists that cannot.
DECLARED="$(
  "${NIX[@]}" eval --impure --raw --expr \
    'builtins.concatStringsSep "\n" (builtins.attrNames (import ./secrets/secrets.nix))' \
    2> /dev/null
)" || DECLARED=""

if [ -z "$DECLARED" ]; then
  echo "  ${RED}could not read secrets/secrets.nix${NC}"
  exit 1
fi

printf "${BOLD}  %-34s %-10s %s${NC}\n" "SECRET" "READERS" "STATE"
while IFS= read -r name; do
  [ -n "$name" ] || continue
  if [ -f "secrets/${name}" ]; then
    n="$(recipients_of "secrets/${name}" | wc -l)"
    kinds="$(recipients_of "secrets/${name}" | sort -u | paste -sd, -)"
    printf "  %-34s %-10s %b\n" "$name" "$n" "${GREEN}encrypted${NC} ${DIM}(${kinds})${NC}"
  else
    printf "  %-34s %-10s %b\n" "$name" "—" "${YELLOW}declared, not yet created${NC}"
  fi
done <<< "$DECLARED"

# The reverse check: an .age file nobody declared has no policy, and agenix
# will not re-key it because it does not know it exists.
ORPHANS=""
for f in secrets/*.age; do
  [ -e "$f" ] || continue
  base="$(basename "$f")"
  grep -q "\"${base}\"" secrets/secrets.nix || ORPHANS="${ORPHANS}  ${base}\n"
done
if [ -n "$ORPHANS" ]; then
  echo
  echo "${RED}Undeclared .age files${NC} ${DIM}— absent from secrets.nix, so never re-keyed:${NC}"
  printf "%b" "$ORPHANS"
fi

if [ "$SHOW_KEYS" -eq 1 ]; then
  echo
  echo "${BOLD}Recipient stanzas per secret${NC}"
  echo "${DIM}(key types only — an age header identifies recipients by tag, not by"
  echo " public key, so this cannot tell you whose key each one is)${NC}"
  for f in secrets/*.age; do
    [ -e "$f" ] || continue
    echo "  ${BOLD}$(basename "$f")${NC}"
    recipients_of "$f" | sed 's/^/    /'
  done
fi

echo
echo "${DIM}──────────────────────────────────────────────────────────────────────${NC}"
echo "${BLUE}💁${NC}  full recipient keys: ${BOLD}kz secrets --recipients${NC}"
echo "${DIM}    edit a secret:       agenix -e secrets/<name>.age${NC}"
echo "${DIM}    re-key after a change to secrets.nix:  agenix -r${NC}"
