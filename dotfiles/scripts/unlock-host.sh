# unlock-host — remote ZFS boot-unlock for a host whose encrypted root pool
# blocks boot until a passphrase is typed into the initrd's SSH server.
# Connects to that early-boot SSH and hands you the passphrase prompt.
#
# No shebang / `set` line on purpose: this fragment is wrapped by
# writeShellApplication (overlays/default.nix), which supplies both.

usage() {
  echo "Usage: unlock-host <lan-ip> <initrd-ssh-port> [initrd-ssh-user]"
  echo ""
  echo "Find the port with hosts/<name>/config.nix's initrdSshPort, or your"
  echo "own fleet registry if you keep one (see hosts/fleet.nix)."
}

port_open() { # host port
  timeout 3 bash -c "</dev/tcp/$1/$2" 2>/dev/null
}

case "${1:-}" in
  "" | -h | --help)
    usage
    exit 0
    ;;
esac

ip="${1:?missing lan-ip — see --help}"
port="${2:?missing initrd-ssh-port — see --help}"
user="${3:-root}"

if ! port_open "$ip" "$port"; then
  echo "$ip's initrd SSH (port $port) is not answering."
  echo "Either the machine is off, still in POST (~30 s), or already booted:"
  if port_open "$ip" 22; then
    echo "  -> port 22 answers: it is already up. Nothing to unlock."
    exit 0
  fi
  exit 1
fi

echo "Connected to $ip's initrd — enter the root pool passphrase below."
echo "(The connection closing afterwards means boot continued: success.)"
exec ssh -t -p "$port" "$user@$ip" systemd-tty-ask-password-agent
