# Kartoza Screencaster — screen/webcam/audio recording with a TUI.
# Custom Kartoza tool (not a COSMIC-repo package), so it lives in the
# generic desktop-apps collection rather than the cosmic module. Part of
{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.kartoza-screencaster # TODO: fix CGO_ENABLED build issue upstream
  ];

  # Autostart into the system tray (X-COSMIC-* is ignored by other DEs).
  environment.etc."xdg/autostart/kartoza-screencaster.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Kartoza Screencaster
    Exec=kartoza-screencaster systray
    Terminal=false
    StartupNotify=false
    X-COSMIC-Autostart-enabled=true
  '';
}
