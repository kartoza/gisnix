{ pkgs, ... }:
{
  # Deploy Kartoza branded fastfetch config
  environment.etc."xdg/fastfetch/config.jsonc" = {
    mode = "0444";
    source = ../../../dotfiles/fastfetch/config.jsonc;
  };

  environment.systemPackages = [
    # Kartoza branded fastfetch wrapper that shows the logo and quick commands
    # Uses the real fastfetch binary path to avoid recursion
    (pkgs.writeShellScriptBin "fastfetch" ''
      ${pkgs.fastfetch}/bin/fastfetch --config /etc/xdg/fastfetch/config.jsonc "$@"

      # Only show the quick commands banner when called without arguments
      if [ $# -eq 0 ]; then
        CYAN='\033[38;2;83;161;203m'
        RESET='\033[0m'
        ORANGE='\033[38;2;223;158;47m'
        GRAY='\033[90m'

        echo -e "''${ORANGE}__________________________________________________________________''${RESET}"
        echo ""
        echo -e "Quick Commands:"
        echo -e "   ''${GRAY}▶''${RESET}  ''${CYAN}f     ''${RESET} - File manager (yazi)"
        echo -e "   ''${GRAY}▶''${RESET}  ''${CYAN}aerc  ''${RESET} - Email client"
        echo -e "   ''${GRAY}▶''${RESET}  ''${CYAN}gurk  ''${RESET} - Signal messenger"
        echo -e "   ''${GRAY}▶''${RESET}  ''${CYAN}nchat ''${RESET} - Telegram & WhatsApp"
        echo -e "   ''${GRAY}▶''${RESET}  ''${CYAN}ns    ''${RESET} - Search nixpkgs"
        echo ""
        echo -e "Keybindings:"
        echo -e "   ''${GRAY}▶''${RESET}  ''${CYAN}Ctrl+T ''${RESET} - Fuzzy find files"
        echo -e "   ''${GRAY}▶''${RESET}  ''${CYAN}Ctrl+R ''${RESET} - Search command history (atuin)"
        echo -e "   ''${GRAY}▶''${RESET}  ''${CYAN}Alt+C  ''${RESET} - Fuzzy cd into directory"
        echo -e "''${ORANGE}__________________________________________________________________''${RESET}"
        echo ""
      fi
    '')
  ];
}
