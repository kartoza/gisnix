# COSMIC Desktop SSH and GPG integration
{
  config,
  lib,
  pkgs,
  ...
}:

{
  # GNOME Keyring for secrets and PKCS#11 only (not SSH)
  # SSH is handled by a dedicated ssh-agent service below
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.cosmic-greeter.enableGnomeKeyring = true;

  # Disable GCR ssh-agent (we use our own ssh-agent)
  services.gnome.gcr-ssh-agent.enable = false;

  # Seahorse for managing keyring entries
  #
  # gcr also matters here for a reason that has nothing to do with seahorse:
  # COSMIC doesn't implement org.gnome.keyring.SystemPrompter itself (see
  # https://github.com/pop-os/cosmic-epoch/issues/3453 — upstream is working
  # on a native one but it hadn't shipped as of epoch 1.10). Whenever
  # gnome-keyring-daemon needs an interactive unlock — e.g. it restarted
  # mid-session and relocked, so the PAM auto-unlock below only applies at
  # login — it calls whoever owns that D-Bus name. With no prompter
  # registered, the request silently times out: no working dialog ever
  # appears, which looks exactly like "I typed the right password and it
  # still didn't unlock." gcr ships GcrSystemPrompter (the dialog gnome-shell
  # normally provides) and its D-Bus service file, so something answers that
  # request under COSMIC too.
  environment.systemPackages = [
    pkgs.seahorse
    pkgs.gcr
  ];

  # Session variables for desktop integration
  environment.sessionVariables = {
    # Wayland for Electron apps
    NIXOS_OZONE_WL = "1";
    # SSH agent socket location
    SSH_AUTH_SOCK = "/run/user/\${UID}/ssh-agent";
  };

  # Dedicated ssh-agent service (clean and simple)
  # Add keys with: ssh-add ~/.ssh/id_ed25519
  #
  # Keys live in the agent's memory only, so they are forgotten at logout.
  # AddKeysToAgent (below) means you type each passphrase once per session
  # rather than once per connection.
  systemd.user.services.ssh-agent = {
    description = "SSH Authentication Agent";
    wantedBy = [ "default.target" ];
    # System users have no /run/user/$UID for the socket to live in.
    unitConfig.ConditionUser = "!@system";
    serviceConfig = {
      Type = "simple";
      Environment = "SSH_AUTH_SOCK=%t/ssh-agent";
      # ssh-agent -a refuses to bind if the path already exists, so a socket
      # left behind by a previous session makes every start fail with exit 1
      # until the restart limit is hit. Upstream nixpkgs clears it the same
      # way (nixos/modules/programs/ssh.nix).
      ExecStartPre = "${pkgs.coreutils}/bin/rm -f %t/ssh-agent";
      ExecStart = "${pkgs.openssh}/bin/ssh-agent -D -a %t/ssh-agent";
      Restart = "on-failure";
    };
  };

  # Load a key into the agent the first time it is used, instead of prompting
  # on every connection. Prompt stays on the terminal (no GUI askpass).
  programs.ssh.extraConfig = ''
    AddKeysToAgent yes
  '';
}
