{ pkgs, ... }:
{
  programs.fish = {
    enable = true;

    # nixpkgs defaults this to true: a separate *_fish-completions.drv per
    # package in the closure, run-command-local so none of them are ever
    # substituted from a binary cache — every COSMIC component, cups, dbus,
    # curl, all of it, built one at a time. That's most of what "installing
    # gisnix" sits at for on a from-scratch install with a real desktop
    # closure. Turning it off costs nothing functional: packages that ship
    # their own fish completions still install them via vendor_completions.d
    # (programs.fish.vendor.completions.enable, on by default), and fish
    # itself generates per-command completions from man pages lazily, on
    # first use, client-side — the same result, just not paid for up front
    # on every single package whether anyone ever tab-completes it or not.
    generateCompletions = false;

    interactiveShellInit = ''
      # Fish shell configuration
      # This replaces the home-manager generated config

      # Only execute this file once per shell
      set -q __fish_system_config_sourced; and exit
      set -g __fish_system_config_sourced 1

      # Set environment variables
      set -gx GPG_TTY (tty)
      set -gx SSH_AUTH_SOCK /run/user/(id -u)/ssh-agent

      if status is-login
          # Login shell initialization
      end

      if status is-interactive
          # Interactive shell initialization

          # Core aliases for better experience
          alias cat 'bat --paging=never'
          alias ls 'eza --icons=always'
          alias ll 'eza -l --icons=always'
          alias la 'eza -a'
          alias l 'eza -alh --icons=always'
          alias lla 'eza -la'
          alias lt 'eza --tree'
          alias tree 'eza --tree'

          # System utilities
          alias htop 'btm --basic --tree --hide_table_gap --dot_marker --mem_as_value'
          alias top 'btm --basic --tree --hide_table_gap --dot_marker --mem_as_value'
          alias find fd
          alias ping gping
          alias less bat
          alias more bat
          alias tail tspin
          alias open xdg-open

          # Development aliases
          alias checkip 'curl -s ifconfig.me/ip'
          alias weather 'wthrr auto -u f,24h,c,mph -f d,w'
          alias weather-home 'wthrr basingstoke -u f,24h,c,mph -f d,w'
          alias moon 'curl -s wttr.in/Moon'
          alias dadjoke 'curl --header "Accept: text/plain" https://icanhazdadjoke.com/'
          alias speedtest speedtest-go

          # System monitoring
          alias dmesg 'dmesg --human --color=always'
          alias ip 'ip --color --brief'

          # Fun utilities
          alias neofetch fastfetch
          alias screenfetch fastfetch
          alias banner figlet
          alias banner-color 'figlet $argv | dotacat'
          alias lolcat dotacat
          alias hr 'hr "─━"'
          alias ruler 'hr "╭─³⁴⁵⁶⁷⁸─╮"'
          alias parrot 'terminal-parrot -delay 50 -loops 7'

          # SSH and networking
          alias ssh 'kitty +kitten ssh'
          alias wormhole wormhole-william

          # File manager
          alias f yazi

          # Development tools
          alias glow 'glow --pager'
          alias psql pgcli
          alias icat 'kitty +kitten icat'
          alias store-path 'readlink (which $argv)'
          alias brg batgrep
          alias gedit gnome-text-editor

          # Lima/containers
          alias make-lima-builder 'lima-create builder'
          alias make-lima-default 'lima-create default'

          # Initialize tools if available
          if command -q starship
              starship init fish | source
          end

          if command -q fzf
              fzf --fish | source
              # fzf provides these keybindings (separate from tab completion):
              # Ctrl+T - Fuzzy find files/dirs and insert path at cursor
              # Alt+C  - Fuzzy cd into a subdirectory
              # Ctrl+R is handled by atuin, so rebind fzf to not use it
              bind --erase \cr
          end

          if command -q zoxide
              zoxide init fish --cmd cd | source
          end

          if command -q direnv
              direnv hook fish | source
          end

          if command -q atuin
              atuin init fish --disable-up-arrow | source
              # Restore fish's native up/down arrow for history navigation
              bind \e\[A history-search-backward
              bind \e\[B history-search-forward
          end

          # Kitty integration
          if set -q KITTY_INSTALLATION_DIR
              set --global KITTY_SHELL_INTEGRATION no-rc
              if test -f "$KITTY_INSTALLATION_DIR/shell-integration/fish/vendor_conf.d/kitty-shell-integration.fish"
                  source "$KITTY_INSTALLATION_DIR/shell-integration/fish/vendor_conf.d/kitty-shell-integration.fish"
                  set --prepend fish_complete_path "$KITTY_INSTALLATION_DIR/shell-integration/fish/vendor_completions.d"
              end
          end

          # Command not found handler
          function __fish_command_not_found_handler --on-event fish_command_not_found
              if command -q command-not-found
                  command-not-found $argv
              end
          end
      end
    '';
  };
  users.defaultUserShell = pkgs.fish;

  # direnv: keep its per-directory load/unload chatter quiet. These used to
  # live in a hand-made ~/.bashrc (now removed); set globally so every shell
  # gets them. (SSH_AUTH_SOCK, the other export in that file, is already set
  # in environment.sessionVariables by cosmic/ssh-gpg.nix.)
  environment.sessionVariables = {
    DIRENV_LOG_FORMAT = "";
    DIRENV_SILENT = "1";
  };

  environment.systemPackages = with pkgs; [
    fish # fish shell like bash but with lots of goodies
    fishPlugins.done
    fishPlugins.forgit
    fishPlugins.hydro
    fzf
    fishPlugins.github-copilot-cli-fish

    # Tools referenced in fish config aliases
    dust # better du
    # fastfetch is provided by fastfetch.nix as a Kartoza branded wrapper
    # batgrep # search with context (package name needs verification)
    zoxide # better cd
    atuin # shell history
    direnv # directory environments

    # Show aliases script - displays fish aliases in a nice table
    (pkgs.writeScriptBin "show-aliases" (builtins.readFile ../../dotfiles/scripts/show-aliases.sh))

    # Deploy script for fish config
    (pkgs.writeScriptBin "deploy-fish-config" ''
      #!/bin/bash
      # Deploy Fish configuration to user's home directory
      USER_HOME="$HOME"
      if [ -z "$USER_HOME" ]; then
        USER_HOME="/home/$USER"
      fi

      echo "Deploying Fish configuration to $USER_HOME..."

      # Create fish config directory
      mkdir -p "$USER_HOME/.config/fish"

      # Remove any existing home-manager symlinks
      if [ -L "$USER_HOME/.config/fish/config.fish" ]; then
        rm "$USER_HOME/.config/fish/config.fish"
      fi

      # Copy configuration file from /etc
      cp /etc/fish/config.fish "$USER_HOME/.config/fish/config.fish"

      # Set permissions
      chmod 644 "$USER_HOME/.config/fish/config.fish"

      echo "Fish configuration deployment complete!"
    '')
  ];

}
