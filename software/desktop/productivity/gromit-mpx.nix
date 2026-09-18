{ pkgs, ... }:
{
  # Gromit-MPX: On-screen annotation and cursor highlight tool
  # Useful for presentations, screen sharing, and teaching
  #
  # Usage:
  #   - Toggle drawing mode: F9 (default hotkey)
  #   - Clear annotations: Shift+F9
  #   - Undo last stroke: Alt+F9
  #   - Toggle visibility: Ctrl+F9
  #
  # Draw with mouse while in drawing mode, press F9 again to return to normal

  environment.systemPackages = with pkgs; [
    gromit-mpx
  ];
}
