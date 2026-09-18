/*
    Gratefully based on https://github.com/Hoverbear-Consulting/flake/blob/89cbf802a0be072108a57421e329f6f013e335a6/traits/hardened.nix

    See:
  * https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/profiles/hardened.nix
  * https://tails.boum.org/contribute/design/kernel_hardening/
*/
{
  pkgs,
  lib,
  projectConfig ? null,
  ...
}:
{
  # imports = [
  #   <nixpkgs/nixos/modules/profiles/hardened.nix>
  # ];

  config = {
    # Ignore ICMP broadcasts to avoid participating in Smurf attacks
    boot.kernel.sysctl."net.ipv4.icmp_echo_ignore_broadcasts" = 1;
    # Ignore bad ICMP errors
    boot.kernel.sysctl."net.ipv4.icmp_ignore_bogus_error_responses" = 1;
    # Reverse-path filter for spoof protection
    boot.kernel.sysctl."net.ipv4.conf.default.rp_filter" = 1;
    boot.kernel.sysctl."net.ipv4.conf.all.rp_filter" = 1;
    # SYN flood protection
    boot.kernel.sysctl."net.ipv4.tcp_syncookies" = 1;
    # Do not accept ICMP redirects (prevent MITM attacks)
    boot.kernel.sysctl."net.ipv4.conf.all.accept_redirects" = 0;
    boot.kernel.sysctl."net.ipv4.conf.default.accept_redirects" = 0;
    boot.kernel.sysctl."net.ipv4.conf.all.secure_redirects" = 0;
    boot.kernel.sysctl."net.ipv4.conf.default.secure_redirects" = 0;
    boot.kernel.sysctl."net.ipv6.conf.all.accept_redirects" = 0;
    boot.kernel.sysctl."net.ipv6.conf.default.accept_redirects" = 0;
    # Do not send ICMP redirects (we are not a router)
    boot.kernel.sysctl."net.ipv4.conf.all.send_redirects" = 0;
    boot.kernel.sysctl."net.ipv4.conf.default.send_redirects" = 0;
    # Do not accept IP source route packets (we are not a router)
    boot.kernel.sysctl."net.ipv4.conf.all.accept_source_route" = 0;
    boot.kernel.sysctl."net.ipv6.conf.all.accept_source_route" = 0;
    # Protect against tcp time-wait assassination hazards
    boot.kernel.sysctl."net.ipv4.tcp_rfc1337" = 1;
    ## Bufferbloat mitigations
    # Requires >= 4.9 & kernel module
    boot.kernel.sysctl."net.ipv4.tcp_congestion_control" = "bbr";
    # Requires >= 4.19
    boot.kernel.sysctl."net.core.default_qdisc" = "cake";

    boot.kernelParams = [
      # Slab/slub sanity checks, redzoning, and poisoning
      "slub_debug=FZP"
      # Clear memory at free, wiping sensitive data
      "page_poison=1"
      # Enable page allocator randomization
      "page_alloc.shuffle=1"
    ];

    #services.openssh.PermitRootLogin = lib.mkForce "no";
    # Only enable fail2ban when not in development mode (requires firewall)
    services.fail2ban.enable = lib.mkDefault (
      projectConfig == null || projectConfig.environmentName != "dev"
    );

    #
    # This section taken from https://dataswamp.org/~solene/2022-01-13-nixos-hardened.html
    # Note that it restricts what part of the file system your browser has access to
    #

    # enable firewall and block all ports
    networking.firewall.enable = true;
    # Note that other services will add ports back in
    networking.firewall.allowedTCPPorts = [ ];
    networking.firewall.allowedUDPPorts = [ ];

    # disable coredump that could be exploited later
    # and also slow down the system when something crash
    systemd.coredump.enable = false;

    # Additional core dump prevention settings
    # Set core file size limit to 0 for all users
    security.pam.loginLimits = [
      {
        domain = "*";
        type = "hard";
        item = "core";
        value = "0";
      }
      {
        domain = "*";
        type = "soft";
        item = "core";
        value = "0";
      }
    ];

    # Kernel parameter to disable core dumps globally
    boot.kernel.sysctl."kernel.core_pattern" = "|/bin/false";

    # required to run chromium
    #security.chromiumSuidSandbox.enable = true;

    # enable firejail
    #programs.firejail.enable = true;

    # create system-wide executables firefox and chromium
    # that will wrap the real binaries so everything
    # work out of the box.
    #programs.firejail.wrappedBinaries = {
    #  firefox = {
    #    executable = "${pkgs.lib.getBin pkgs.firefox}/bin/firefox";
    #    profile = "${pkgs.firejail}/etc/firejail/firefox.profile";
    #  };
    #  chromium = {
    #    executable = "${pkgs.lib.getBin pkgs.chromium}/bin/chromium";
    #    profile = "${pkgs.firejail}/etc/firejail/chromium.profile";
    #  };
    #};

    # enable antivirus clamav and
    # keep the signatures' database updated
    #services.clamav.daemon.enable = true;
    #services.clamav.updater.enable = true;
  };
}
