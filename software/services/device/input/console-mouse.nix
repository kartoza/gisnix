{
  config,
  pkgs,
  ...
}:
{
  # Console mouse support with GPM and libinput trackpad configuration

  environment.systemPackages = with pkgs; [
    gpm
  ];

  # Enable GPM (General Purpose Mouse) for console mouse support
  services.gpm = {
    enable = true;
    protocol = "evdev";
  };

  # Configure libinput for trackpad with palm rejection
  services.libinput = {
    enable = true;
    touchpad = {
      tapping = true;
      naturalScrolling = true;
      disableWhileTyping = true;
      sendEventsMode = "enabled";
      # clickfinger: two-finger tap = right-click, three-finger tap = middle-click
      clickMethod = "clickfinger";
      additionalOptions = ''
        Option "PalmDetection" "on"
        Option "PalmMinWidth" "8"
        Option "PalmMinZ" "200"
      '';
    };
  };

  # libinput quirks for PixArt touchpad - improves palm detection and reduces cursor jumps
  # This applies at the libinput level and works with Wayland compositors like niri
  environment.etc."libinput/local-overrides.quirks" = {
    mode = "0644";
    text = ''
      # PixArt touchpad palm detection and sensitivity tuning
      # Device: PIXA3854:00 093A:0274 Touchpad
      [PixArt Touchpad Palm Detection]
      MatchName=*PIXA*Touchpad*
      MatchBus=i2c
      AttrPalmPressureThreshold=150
      AttrPressureRange=8:5

      # Alternative match by vendor/product ID
      [PixArt 093A:0274 Touchpad]
      MatchVendor=0x093A
      MatchProduct=0x0274
      AttrPalmPressureThreshold=150
      AttrPressureRange=8:5
    '';
  };
}
