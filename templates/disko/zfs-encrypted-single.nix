# Single-disk, ZFS-encrypted disko layout — the gisnix installer's
# recommended default. Passphrase-encrypted (aes-256-gcm, prompted at
# boot), so the disk is unreadable without it. Mirrors the dataset
# layout every ZFS host in the wild already uses: root/nix/home/overflow
# datasets plus an XFS zvol for shell history, so `gisnix configure`/`gisnix
# update` behave identically to a hand-installed host.
#
#   disk = mkZfsEncryptedSingle { device = "/dev/sda"; }
{
  device,
  poolName ? "NIXROOT",
  espSize ? "5G",
  # Fallback defaults for a standalone `import` of this template outside
  # the installer (e.g. by hand, or `gisnix create-host`). The installer
  # itself always overrides all four via installer/sizing.py, sized
  # against the real disk so they leave headroom instead of risking a
  # 0-byte-free pool — see that module's docstring.
  rootQuota ? "10G",
  nixQuota ? "20G",
  homeQuota ? "20G",
  overflowQuota ? "10G",
  atuinSize ? "1G",
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
    };

    zpool = {
      ${poolName} = {
        type = "zpool";
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
          # The flagship feature: passphrase-encrypted at rest. The
          # passphrase is typed once at boot (keylocation = prompt) and
          # unlocks every dataset below it (single encryption root).
          encryption = "aes-256-gcm";
          keyformat = "passphrase";
          keylocation = "prompt";
          "com.sun:auto-snapshot" = "false";
        };

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

          "overflow" = {
            type = "zfs_fs";
            mountpoint = "/overflow";
            options = {
              "com.sun:auto-snapshot" = "true";
              quota = overflowQuota;
            };
          };

          "atuin" = {
            type = "zfs_volume";
            size = atuinSize;
            content = {
              type = "filesystem";
              format = "xfs";
              mountpoint = "/var/atuin";
              mountOptions = [
                "defaults"
                "nofail"
              ];
            };
          };
        };
      };
    };
  };
}
