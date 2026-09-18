{
  config,
  pkgs,
  ...
}:
{
  # Note mutually exclusive with the podman service
  environment.systemPackages = with pkgs; [
    docker-compose
  ];

  virtualisation.docker.enable = true;
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
  };
  boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = 50;
}
