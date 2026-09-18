# Gatus Monitor — system-tray app for watching Gatus health-check
# endpoints. Custom Kartoza tool (not a COSMIC-repo package); lives in
# the generic desktop-apps collection. Slim-gated.
{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.gatus-monitor ];

  environment.etc = {
    "share/applications/gatus-monitor.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Gatus Monitor
      Comment=Monitor Gatus health check endpoints
      Exec=gatus-monitor
      Terminal=false
      StartupNotify=false
      Icon=gatus-monitor
      Categories=Utility;Monitor;
    '';
    "xdg/autostart/gatus-monitor.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Gatus Monitor
      Comment=Monitor Gatus health check endpoints
      Exec=gatus-monitor
      Terminal=false
      StartupNotify=false
      Icon=gatus-monitor
      Categories=Utility;Monitor;
      X-COSMIC-Autostart-enabled=true
    '';
  };
}
