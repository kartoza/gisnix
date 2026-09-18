{ pkgs, ... }:
{
  # Local snapshot policy for /home.
  #
  # sanoid takes frequent snapshots of NIXROOT/home in the background whenever
  # the machine is on. Offload is a SEPARATE, manual step: when the USB backup
  # drive is attached, `zfs-backup` zfs-sends these snapshots to the USB pool and
  # replaces the sent snapshots with bookmarks.
  #
  # There is deliberately NO syncoid replication target here. The previous
  # `services.syncoid` job targeted a pool `b` (b/home) that does not exist, so
  # it failed on every 15-minute run and left an orphaned snapshot behind each
  # time — the source of the hundreds of unpruned NIXROOT/home@syncoid_* snaps.
  services.sanoid = {
    enable = true;

    # Run on the absolute wall clock at :00 :15 :30 :45 — NOT relative to boot.
    interval = "*:0/15";

    datasets."NIXROOT/home" = {
      useTemplate = [ "home" ];
    };

    templates.home = {
      # 15-minute snapshots. `frequently` is how many are kept; 96 = 24h of
      # them. Keep this comfortably LARGER than the longest expected gap between
      # USB backups, so sanoid never prunes a snapshot before zfs-backup has
      # offloaded it to the USB pool.
      frequent_period = 15;
      frequently = 96;
      hourly = 36;
      daily = 30;
      monthly = 12;
      yearly = 4;
      autosnap = true;
      autoprune = true;
    };
  };

  # The sanoid systemd timer defaults to AccuracySec=1min, which jitters each
  # snapshot several seconds/minutes past the quarter-hour. Pin it to 1s so the
  # snapshots land exactly on :00 :15 :30 :45.
  systemd.timers.sanoid.timerConfig.AccuracySec = "1s";

  environment.systemPackages = with pkgs; [
    pv # progress meter used by zfs sends (zfs-backup / syncoid)
    sanoid # provides both the sanoid and syncoid CLIs
  ];
}
