# Multi-disk ZFS layout — stripe (no redundancy), raidz (1-disk fault
# tolerance, 3+ disks), or raidz2 (2-disk fault tolerance, 4+ disks).
# Same encrypted/dataset shape as zfs-encrypted-single.nix, just spread
# across N disks under one vdev mode.
#
#   disk = mkZfsMulti {
#     devices = [ "/dev/nvme0n1" "/dev/nvme1n1" ];
#     mode = "raidz"; # "stripe" | "raidz" | "raidz2"
#     encrypted = true;
#   }
{
  devices,
  mode ? "raidz",
  encrypted ? true,
  poolName ? "NIXROOT",
  espSize ? "5G",
  # Fallback defaults for a standalone `import` outside the installer —
  # it always overrides these via installer/sizing.py, sized against the
  # real pool capacity. See zfs-encrypted-single.nix's matching comment.
  rootQuota ? "20G",
  nixQuota ? "300G",
  homeQuota ? "300G",
}:
let
  minDisks = {
    stripe = 2;
    raidz = 3;
    raidz2 = 4;
  };
in
assert builtins.length devices >= (minDisks.${mode} or 2);
let
  diskEntries = builtins.listToAttrs (
    builtins.genList (i: {
      name = "disk${toString i}";
      value = {
        type = "disk";
        device = builtins.elemAt devices i;
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00";
              size = espSize;
              content = {
                type = "filesystem";
                format = "vfat";
                mountOptions = [ "umask=0077" ];
                # Only the first ESP is actually mounted at /boot;
                # the rest exist so any disk can boot if one fails.
                mountpoint = if i == 0 then "/boot" else null;
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = poolName;
              };
            };
          };
        };
      };
    }) (builtins.length devices)
  );

  zpoolMode = if mode == "stripe" then null else mode;
in
{
  disko.devices = {
    disk = diskEntries;

    zpool = {
      ${poolName} = {
        type = "zpool";
        mode = zpoolMode;
        options = {
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = {
          compression = "zstd";
          acltype = "posixacl";
          xattr = "sa";
          relatime = "on";
          mountpoint = "none";
          "com.sun:auto-snapshot" = "false";
        }
        // (
          if encrypted then
            {
              encryption = "aes-256-gcm";
              keyformat = "passphrase";
              keylocation = "prompt";
            }
          else
            { }
        );

        datasets = {
          "root" = {
            type = "zfs_fs";
            mountpoint = "/";
            options = {
              "com.sun:auto-snapshot" = "false";
              quota = rootQuota;
            };
            postCreateHook = "zfs snapshot ${poolName}/root@blank";
          };
          "nix" = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options = {
              "com.sun:auto-snapshot" = "false";
              quota = nixQuota;
            };
          };
          "home" = {
            type = "zfs_fs";
            mountpoint = "/home";
            options = {
              "com.sun:auto-snapshot" = "true";
              quota = homeQuota;
            };
          };
        };
      };
    };
  };
}
