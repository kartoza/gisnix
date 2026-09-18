{ config, pkgs, ... }:
{
  # Note:
  #
  # scrcpy is an app similar to uxplay that allows you to
  # cast your android device to a window in linux
  #
  #
  # We make an alias below for convenient launching when using oculus quest 2

  programs.fish.shellAliases = {
    # see https://stackoverflow.com/a/73202796
    ax-oculus = "scrcpy --crop 1730:974:1934:450 --max-fps 30";
  };
  environment.systemPackages = with pkgs; [
    scrcpy
    android-tools
  ];
  # android-tools is included in systemPackages above for adb support
  # (programs.adb is no longer needed as systemd 258 handles uaccess rules automatically)

}
