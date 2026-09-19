{ ... }:
{
  # Compressed swap in RAM.
  #
  # Every host in this flake sets swapDevices = [ ], which leaves the kernel no
  # cushion at all: under pressure it can only reclaim page cache or start
  # killing. Without zram that produces a global OOM kill that takes out a
  # browser and a game while the desktop session survives, presenting as "all
  # my apps closed by themselves".
  #
  # It also disables the graceful path. systemd-oomd starts, logs "No swap;
  # memory pressure usage will be degraded", and monitors nothing — so the
  # indiscriminate kernel OOM killer does the work instead of oomd's targeted,
  # pressure-driven kill.
  #
  # WHY ZRAM AND NOT A SWAP FILE: the root pools here are ZFS, and swapping to a
  # ZVOL or a file on ZFS is a long-standing deadlock risk (the writeback path
  # can re-enter ZFS while it is trying to free memory). zram is a compressed
  # block device in RAM, so it never touches the pool.
  #
  # tmpfs pages are the specific thing this rescues. Without swap they cannot be
  # evicted at all, only freed — which is why the agent sandboxes' $HOME tmpfs
  # mounts pinned 66 GiB of unevictable shmem. With zram they become pageable.
  zramSwap = {
    enable = true;
    # Percentage of RAM the compressed device may represent. 25% is the common
    # default; zstd typically achieves 3:1 on anonymous pages, so this costs
    # well under 10% of real RAM at full utilisation.
    memoryPercent = 25;
    algorithm = "zstd";
  };

  # Give zram a strong preference over reclaiming page cache. The kernel default
  # of 60 is tuned for slow disk-backed swap; zram is RAM-speed, so leaning on
  # it is cheaper than evicting cache we are about to re-read.
  boot.kernel.sysctl = {
    "vm.swappiness" = 180;
    # Matching pair for zram: do not spend effort on readahead (there is no
    # seek cost) and reclaim aggressively enough to keep a free margin.
    "vm.page-cluster" = 0;
    "vm.watermark_boost_factor" = 0;
    "vm.watermark_scale_factor" = 125;
  };
}
