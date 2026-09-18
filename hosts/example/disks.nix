# Disk layout for the example host. ZFS-encrypted single disk by default —
# the installer's recommended choice — built from the shared template so
# every ZFS-encrypted host in the fleet shares one dataset layout. Swap the
# import below for templates/disko/xfs-single.nix (plain, unencrypted) or
# templates/disko/zfs-multi.nix (stripe/raidz/raidz2 across several disks)
# to try the other storage modes the installer offers.
import ../../templates/disko/zfs-encrypted-single.nix { device = "/dev/sda"; }
