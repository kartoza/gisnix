# Single-disk, unencrypted XFS layout — the plain alternative to ZFS
# encryption, for machines that need maximum performance/latest-kernel
# compatibility or are dual-booting alongside an existing install.
#
#   disk = mkXfsSingle { device = "/dev/sda"; }
{
  device,
  espSize ? "1G",
}:
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = device;
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00";
              size = espSize;
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "xfs";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
