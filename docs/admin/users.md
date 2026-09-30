# Managing users

A user account on a GISNIX machine is described in a file, like everything
else: `users/<name>.nix` holds the account, and each host that should have that
user imports it. You can write those by hand, but `gisnix adduser` does the
whole thing for you — including the parts that are easy to get wrong, like
hashing the password and fetching an SSH key.

## Adding a user

```bash
gisnix adduser
```

It asks, in turn:

- **Username** — lowercase, the login name.
- **Full name** — what shows up in the greeter and `finger`-style listings.
- **GitHub username** *(optional)* — GISNIX fetches that account's public keys
  from `github.com/<user>.keys` and installs them, so you never paste a key by
  hand. You can skip this and add keys later.
- **Password** — entered twice, then hashed with `mkpasswd` and written into
  the user file as `hashedPassword`. The plaintext is never stored anywhere.
- **Which hosts** — a checklist of every host in your flake. The user is added
  to the ones you tick.

For each host you chose, `gisnix adduser` writes `users/<name>.nix` and adds an
import of it to that host's `hosts/<host>/default.nix`. Nothing is written until
every file it would create or change has been checked with `nix-instantiate
--parse`, so a mistake leaves your tree exactly as it was. Then apply it:

```bash
gisnix update            # this machine
```

## How a machine authenticates you

GISNIX runs sshd on every machine, but locked down, so it is worth knowing how
you actually get in:

- **Public keys only.** Password login over SSH is off, and so is root login.
  The keys you gave `adduser` (or added by hand) are what let you in. NixOS
  writes them to a managed file (`/etc/ssh/authorized_keys.d/<user>`), which is
  why you will not find them in `~/.ssh/authorized_keys` — that path also works
  if you add one, but the managed file is the one `adduser` populates.
- **Local network and VPN only.** Port 22 is not open to the whole internet.
  It is reachable from the private ranges (`192.168.0.0/16`, `10.0.0.0/8`) and
  the overlay VPN, and closed everywhere else.

The practical upshot: give `adduser` a GitHub username with a real key on it,
or that account can log in at the physical console but not over SSH. If you are
ever locked out at a console you *can* reach, add a key to
`~/.ssh/authorized_keys` and it takes effect immediately, no rebuild.

## Changing or removing a user

`users/<name>.nix` is a normal module — edit it and `gisnix update`:

- **Add or change SSH keys** — edit `openssh.authorizedKeys.keys`.
- **Change groups, shell, or the description** — edit the fields on
  `users.users.<name>`.
- **Remove the user from a host** — delete the `../../users/<name>.nix` import
  from that host's `hosts/<host>/default.nix`. Removing the account entirely is
  deleting the user file and every import of it. (NixOS will not delete the
  user's home directory on rebuild — that is left for you to do deliberately.)

The full per-flag detail for the command is in the
[commands reference](../references/commands.md#adduser).
