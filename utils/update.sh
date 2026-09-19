#!/usr/bin/env bash
#
# update — push this flake's configuration to one host, several, or all of them.
#
# This replaces three scripts that had grown apart: rebuild.sh (this machine),
# rebuild-remote-host.sh (build here, copy, activate there) and
# sync-michelle.sh (rsync the tree, then build on the target). They were three
# because each host needed a different mechanism — but which mechanism a host
# needs is a fact about the host, so it now lives in hosts/fleet.nix as the
# `deploy` field and this one command dispatches on it:
#
#   local   rebuild in place, on the machine you are sitting at
#   ssh     build here, sign, copy the closure over, activate remotely.
#           For hosts that should not build (laptops) or cannot fetch this
#           flake's inputs themselves.
#   rsync   copy the working tree over, then build there with --target-host.
#           For hosts whose nix store cannot reach our inputs at all.
#   none    not deployed — use `gisnix <host>-vm` instead.
#
# Usage:
#   gisnix update                  # this machine
#   gisnix update abyss waterfall  # named hosts
#   gisnix update --all         # every deployable host
#   gisnix update --check       # dry-activate; changes nothing
#   gisnix update --boot        # apply on next boot, not now
#   gisnix update --no-gc       # skip the cleanup prompt (local only)
#
# The remote paths need your key in ssh-agent and the target reachable —
# `gisnix inventory` will tell you which hosts are answering.
set -uo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[38;2;88;150;50m'
YELLOW=$'\033[38;2;240;230;74m'
BLUE=$'\033[38;2;147;176;35m'
ORANGE=$'\033[38;2;238;121;19m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
NC=$'\033[0m'

info() { echo "  ${BLUE}💁  $1${NC}"; }
ok() { echo "  ${GREEN}✅  $1${NC}"; }
warn() { echo "  ${YELLOW}⚠️   $1${NC}"; }
err() { echo "  ${RED}❌  $1${NC}"; }
step() { echo; echo "${BOLD}${GREEN}▸ $1${NC}"; }
cmd() { echo "  ${ORANGE}${BOLD}\$ $1${NC}"; }

TARGETS=()
# Invoking this as `update-all` is the same as `update --all`. Two menu rows,
# one script: pushing to the whole fleet is common enough to deserve its own
# entry, and a flag buried in a row description gets missed.
case "$(basename "$0")" in
  update-all) ALL=1 ;;
  *) ALL=0 ;;
esac
MODE=switch
DO_GC=1

while (($# > 0)); do
  case "$1" in
    -h | --help)
      awk 'NR>1 && /^# shellcheck/ {next} NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"
      exit 0
      ;;
    --all) ALL=1 ;;
    --check) MODE=dry-activate ;;
    --boot) MODE=boot ;;
    --no-gc) DO_GC=0 ;;
    -*)
      err "unknown flag: $1"
      exit 1
      ;;
    *) TARGETS+=("$1") ;;
  esac
  shift
done

[[ -f ./hosts/fleet.nix ]] || {
  err "run from the repo root (hosts/fleet.nix missing)."
  exit 1
}

NIX=(nix --extra-experimental-features 'nix-command flakes')

host_field() { # $1=host $2=field $3=default
  "${NIX[@]}" eval --raw --impure --expr \
    "let h = (import ./hosts/fleet.nix).hosts.$1 or {}; v = h.$2 or null;
     in if v == null then \"$3\" else v" 2>/dev/null || echo "$3"
}

mapfile -t ALL_HOSTS < <(
  "${NIX[@]}" eval --impure --raw --expr \
    'builtins.concatStringsSep "\n" (builtins.attrNames (import ./hosts/fleet.nix).hosts)' 2>/dev/null
)
[[ ${#ALL_HOSTS[@]} -gt 0 ]] || {
  err "could not read the host list from hosts/fleet.nix"
  exit 1
}

if ((ALL)); then
  TARGETS=()
  for h in "${ALL_HOSTS[@]}"; do
    [[ "$(host_field "$h" deploy ssh)" == "none" ]] || TARGETS+=("$h")
  done
elif [[ ${#TARGETS[@]} -eq 0 ]]; then
  self="$(hostname -s 2>/dev/null || true)"
  for h in "${ALL_HOSTS[@]}"; do [[ "$h" == "$self" ]] && TARGETS=("$h"); done
  [[ ${#TARGETS[@]} -gt 0 ]] || {
    err "this machine (${self:-unknown}) is not a host in hosts/fleet.nix."
    info "name a host explicitly, or use --all. Known hosts: ${ALL_HOSTS[*]}"
    exit 1
  }
  info "no host given — defaulting to this machine: ${BOLD}${TARGETS[0]}${NC}"
fi

# Validate before doing anything, so a typo in a multi-host run fails fast
# rather than after the first host has already switched.
for h in "${TARGETS[@]}"; do
  found=0
  for known in "${ALL_HOSTS[@]}"; do [[ "$h" == "$known" ]] && found=1; done
  ((found)) || {
    err "'$h' is not a host in hosts/fleet.nix"
    info "known hosts: ${ALL_HOSTS[*]}"
    exit 1
  }
done

# ── The three deployment mechanisms ────────────────────────────────────────

deploy_local() { # $1=host
  local host="$1"
  step "$host — rebuilding in place (${MODE})"

  # This directory is recreated by something in the GTK stack on every switch
  # and then trips the next one up. Clearing it first is cheaper than tracking
  # down which package does it.
  rm -rf ~/.gtkrc-2.0.backup-dirty

  cmd "sudo nixos-rebuild ${MODE} --flake .#${host}"
  sudo nixos-rebuild "$MODE" --fast --flake ".#${host}" --option max-jobs auto || {
    err "rebuild failed — nothing was changed"
    return 1
  }
  ok "rebuild completed"

  [[ "$MODE" == "switch" ]] || return 0

  # Units whose ExecStart embeds a /nix/store path keep running the old build
  # until they are explicitly restarted; a switch does not do it for user
  # services.
  if systemctl --user list-unit-files razer-layer-lights.service >/dev/null 2>&1 &&
    systemctl --user is-enabled razer-layer-lights.service >/dev/null 2>&1; then
    info "restarting razer-layer-lights (its ExecStart is a store path)"
    systemctl --user restart razer-layer-lights.service 2>/dev/null || true
  fi

  if command -v niri >/dev/null 2>&1 && pgrep -x niri >/dev/null; then
    info "reloading niri config"
    niri msg reload-config 2>/dev/null || true
  fi

  ((DO_GC)) || return 0
  command -v gum >/dev/null 2>&1 || return 0
  echo
  gum confirm "Clean up old generations (keeping the last 10) and collect garbage?" --default=false || {
    info "skipping cleanup"
    return 0
  }
  step "$host — cleaning up"
  sudo nix-env --delete-generations +10 --profile /nix/var/nix/profiles/system
  if command -v home-manager >/dev/null 2>&1; then
    home-manager expire-generations '-10' || true
  fi
  sudo nix-collect-garbage
  ok "cleanup complete"
}

deploy_ssh() { # $1=host
  local host="$1"
  local user addr target
  user="$(host_field "$host" sshUser "$(id -un)")"
  addr="$(host_field "$host" lanAddress '')"
  target="${addr:-$host}"

  step "$host — build here, activate on ${user}@${target} (${MODE})"

  # A locally-built closure is unsigned, so the remote daemon rejects it. Sign
  # with a local key and copy through `sudo nix-daemon`, which bypasses the
  # signature check for a trusted invocation. Generated once, on first use.
  local sign_key="$HOME/.config/nix/local-build-key.sec"
  local sign_pub="$HOME/.config/nix/local-build-key.pub"
  if [[ ! -f "$sign_key" ]]; then
    info "generating a local signing key (first run)"
    mkdir -p "$(dirname "$sign_key")"
    "${NIX[@]}" key generate-secret --key-name local-build > "$sign_key"
    "${NIX[@]}" key convert-secret-to-public < "$sign_key" > "$sign_pub"
    info "public key: $(cat "$sign_pub")"
  fi

  local system_path
  cmd "nix build .#nixosConfigurations.${host}.config.system.build.toplevel"
  system_path="$("${NIX[@]}" build --print-out-paths --no-link \
    ".#nixosConfigurations.${host}.config.system.build.toplevel")" || {
    err "build failed for $host"
    return 1
  }
  ok "built ${system_path}"

  # Checked, unlike before: a silent failure here produced an unsigned
  # closure and the confusing "lacks a signature by a trusted key" from the
  # far end, which reads as a problem with the remote rather than with us.
  "${NIX[@]}" store sign --recursive --key-file "$sign_key" "$system_path" || {
    err "could not sign the closure with $sign_key"
    return 1
  }

  # --no-check-sigs is what actually makes this work, and it is not the
  # blunt instrument it looks like.
  #
  # A trusted connection does not skip signature checking; it only means the
  # daemon will HONOUR a request to skip it. Without the flag, nix copy checks
  # by default, the check runs against the target's trusted-public-keys, our
  # build key is not there until the target has been deployed to once, and the
  # copy fails with "lacks a signature by a trusted key" — the deadlock that
  # stopped waterfall being deployed to at all.
  #
  # Measured on waterfall, copying one small path four ways: plain FAILED,
  # plain --no-check-sigs SUCCEEDED, with `Trusted: 1` reported either way.
  #
  # We are not lowering a defence: this closure was built on this machine
  # moments ago, and the target already trusts this user enough to run
  # switch-to-configuration under sudo a few lines below. The signature above
  # is still made, and profiles/common.nix now trusts the key, so once a host
  # has been deployed to it can verify rather than take our word for it.
  cmd "nix copy --to ssh-ng://${user}@${target}"
  NIX_SSHOPTS="-o StrictHostKeyChecking=accept-new" \
    "${NIX[@]}" copy --no-check-sigs \
    --to "ssh-ng://${user}@${target}?remote-program=sudo nix-daemon --stdio" \
    "$system_path" || {
    err "could not copy the closure to $target"
    info "${user} must be in nix.settings.trusted-users on $target — that is"
    info "what lets us ask it to skip the signature check on a closure we"
    info "just built. profiles/common.nix declares it, so the usual cause is"
    info "that $target has not been rebuilt since. Check with:"
    info "  ssh ${user}@${target} grep -E 'trusted-users' /etc/nix/nix.conf"
    return 1
  }

  if [[ "$MODE" == "dry-activate" ]]; then
    info "--check: closure is on the host but nothing was activated"
    # SC2029: $system_path expanding client-side is the point — it is the path
    # we just built and copied here, and the remote must be told exactly that.
    # shellcheck disable=SC2029
    ssh "${user}@${target}" "sudo ${system_path}/bin/switch-to-configuration dry-activate"
    return $?
  fi

  cmd "switch-to-configuration ${MODE} on ${target}"
  # shellcheck disable=SC2029  # see above: client-side expansion is intended
  ssh "${user}@${target}" \
    "sudo nix-env -p /nix/var/nix/profiles/system --set ${system_path} \
     && sudo ${system_path}/bin/switch-to-configuration ${MODE}" || {
    err "activation failed on $target"
    return 1
  }
  ok "$host updated"
}

deploy_rsync() { # $1=host
  local host="$1"
  local user addr target path repo
  user="$(host_field "$host" sshUser "$(id -un)")"
  addr="$(host_field "$host" lanAddress '')"
  target="${addr:-$host}"
  path="/home/${user}/dev/nix-config/"
  # NOT derived from BASH_SOURCE. This script is baked into a
  # writeShellApplication, so at runtime BASH_SOURCE[0] is
  # /nix/store/...-update/bin/update and its parent is the DERIVATION — which
  # is what got rsync'd over a target's checkout. `gisnix` cds to the repo root
  # before dispatching, so the working tree is simply where we are.
  repo="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

  step "$host — rsync the tree to ${user}@${target}, then build there (${MODE})"

  # .git is excluded deliberately: a stale .git on the target makes the flake
  # evaluate whatever that copy last committed rather than what was just
  # synced, which silently deploys the wrong configuration.
  cmd "rsync ${repo}/ ${user}@${target}:${path}"
  rsync -a --info=stats1 \
    --filter=':- .gitignore' \
    --exclude='.git' \
    "${repo}/" "${user}@${target}:${path}" || {
    err "rsync to $target failed"
    return 1
  }

  cmd "nixos-rebuild ${MODE} --flake ${repo}#${host} --target-host ${user}@${target}"
  nixos-rebuild "$MODE" \
    --flake "${repo}#${host}" \
    --target-host "${user}@${target}" \
    --use-remote-sudo || {
    err "remote rebuild failed for $host"
    return 1
  }
  ok "$host updated"
}

# ── Run ────────────────────────────────────────────────────────────────────

echo
echo "${BOLD}update${NC}  ${DIM}mode: ${MODE}   ·   targets: ${TARGETS[*]}${NC}"

failed=()
for host in "${TARGETS[@]}"; do
  method="$(host_field "$host" deploy ssh)"

  # Being ON the machine beats whatever fleet.nix says about reaching it.
  # atoll is registered as deploy = "rsync", so running `gisnix update` while
  # sitting at atoll rsync'd the tree to atoll over the VPN and then built it
  # there over SSH — the machine copying to itself, as timlinux, needing a
  # host key for its own address. `deploy` describes how to reach a host from
  # somewhere else; it says nothing about what to do when you are already
  # there.
  if [[ "$host" == "$(hostname -s 2>/dev/null)" ]]; then
    [[ "$method" == "local" ]] || info "this is ${BOLD}${host}${NC} — rebuilding in place rather than over ${method}"
    method=local
  fi
  case "$method" in
    local) deploy_local "$host" || failed+=("$host") ;;
    ssh) deploy_ssh "$host" || failed+=("$host") ;;
    rsync) deploy_rsync "$host" || failed+=("$host") ;;
    none)
      warn "$host is not deployed (deploy = \"none\") — run it as a VM instead:"
      cmd "gisnix ${host}-vm"
      ;;
    *)
      err "$host has an unknown deploy method '${method}' in hosts/fleet.nix"
      failed+=("$host")
      ;;
  esac
done

echo
if [[ ${#failed[@]} -eq 0 ]]; then
  ok "all done"
else
  err "failed: ${failed[*]}"
  exit 1
fi
