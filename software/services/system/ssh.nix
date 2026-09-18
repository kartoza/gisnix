{
  config,
  pkgs,
  lib,
  ...
}:
{
  # GPG agent for signing commits and encrypting files
  # SSH handled by GNOME Keyring on desktop systems
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = false;
    pinentryPackage = pkgs.pinentry-gnome3;
  };

  # Don't start ssh-agent here. COSMIC desktops run their own ssh-agent user
  # service (software/desktop/environments/cosmic/ssh-gpg.nix); GNOME Keyring is
  # deliberately NOT the SSH agent, and gcr-ssh-agent is disabled there too.
  programs.ssh.startAgent = lib.mkDefault false;
  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    allowSFTP = false; # Don't set this if you need sftp
    #settings.KbdInteractiveAuthentication = false;
    extraConfig = ''
      AllowTcpForwarding yes
      X11Forwarding no
      AllowAgentForwarding no
      AllowStreamLocalForwarding no
      AuthenticationMethods publickey
      Banner /etc/issue.net
    '';
    settings.PrintMotd = true;
    settings.Banner = "/etc/issue.net";

    authorizedKeysFiles = [ "~/.ssh/authorized_keys" ];
    settings.PermitRootLogin = lib.mkDefault "no";
    settings.PasswordAuthentication = false; # originally true
    #challengeResponseAuthentication = false;
  };
}
