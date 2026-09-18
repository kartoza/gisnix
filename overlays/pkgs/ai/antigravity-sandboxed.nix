{ callPackage, antigravity }:

# Antigravity (VS Code-fork Electron IDE) wrapped in bubblewrap.
# GUI plumbing (Wayland/X11/DBus/GPU/fonts) is exposed via gui = true.
# Electron's internal chrome-sandbox is disabled (--no-sandbox) because bwrap
# is already the outer security boundary and the SUID helper interacts poorly
# with bwrap's user namespace.
callPackage ./mk-sandboxed.nix { } {
  name = "antigravity-sandboxed";
  command = "antigravity";
  exe = "${antigravity}/bin/antigravity";
  extraArgs = [ "--no-sandbox" ];
  gui = true;
  stateDirs = [
    ".antigravity"
    ".config/Antigravity"
    ".cache/Antigravity"
  ];
  meta.description = "Antigravity IDE, bubblewrap-sandboxed";
}
