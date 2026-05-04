_: let
  c = import ./lib/colors.nix;
in {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    defaultKeymap = "viins";

    initContent = ''
      # Set zsh options
      setopt NO_BEEP
      setopt NO_FLOW_CONTROL
      setopt PROMPT_SUBST
      setopt LONG_LIST_JOBS
      setopt NONOMATCH
      setopt NOTIFY
      setopt HASH_LIST_ALL
      setopt COMPLETE_IN_WORD
      setopt NO_SH_WORD_SPLIT
      setopt INTERACTIVE_COMMENTS

      # Kitty terminal configuration
      if [[ "$TERM" == "xterm-kitty" ]]; then
        export TERM="xterm-256color"
        alias ssh="kitty +kitten ssh"
      fi

      # Enable VS Code terminal shell integration even with custom zsh init.
      if [[ "$TERM_PROGRAM" == "vscode" || "$TERM_PROGRAM" == "vscode-insiders" ]]; then
        if command -v code-insiders >/dev/null 2>&1; then
          source "$(code-insiders --locate-shell-integration-path zsh)"
        elif command -v code >/dev/null 2>&1; then
          source "$(code --locate-shell-integration-path zsh)"
        fi
      fi

      # Initialize shell integrations
      eval "$(zoxide init zsh)"

      # FZF integration
      if command -v fzf >/dev/null 2>&1; then
        source <(fzf --zsh)
      fi

      # Initialize Starship through PATH so shell startup does not depend on a
      # hardcoded store or Homebrew path.
      if [[ "$TERM" != "dumb" ]] && command -v starship >/dev/null 2>&1; then
        eval "$(starship init zsh)"
      fi
    '';

    shellAliases = {
      rsync-cp = "rsync -avzhi --filter=':- .gitignore' --exclude='node_modules' --exclude='.venv' --compress-choice=zstd --info=progress2 --stats";
      rsync-mv = "rsync -avz --compress-choice=zstd --progress -h --remove-source-files";
      rsync-update = "rsync -avzu --compress-choice=zstd --progress -h";
      rsync-sync = "rsync -avzu --compress-choice=zstd --delete --info=progress2 --no-whole-file -h";

      rsync-bak = "rsync -avbuzh --numeric-ids --compress-choice=zstd --progress --backup-dir={{.xdg_cache_home}}/rsync";

      cat = "bat --pager=never";
      top = "sudo htop";
      du = "ncdu --color dark -rr -x --exclude .git --exclude node_modules";

      # Modern replacements
      ls = "eza --icons"; # ls
      l = "eza -lbF --git --icons"; # list, size, type, git
      ll = "eza -lbGF --git --icons"; # long list
      ltr = "eza -lbGd --git --sort=modified --icons"; # long list, modified date sort
      llm = "eza --all --header --long --sort=modified $eza_params";
      la = "eza -lbhHigUmuSa --git --color-scale --icons"; # all list
      lx = "eza -lbhHigUmuSa@ --git --color-scale --icons"; # all + extended list

      # Zoxide shortcuts
      cd = "z"; # Use zoxide instead of cd
    };

    envExtra = ''
          # If an old standalone Home Manager profile path is present, remove it.
          # nix-darwin + home-manager module exposes the right profile via /etc/profiles.
          path=(''${path:#$HOME/.local/state/nix/profiles/home-manager/home-path/bin})
          export PATH=''${(j/:/)path}

          # Prefer nix-darwin system/user profiles early in PATH.
          # This avoids accidentally running stale binaries from an inherited PATH.
          if [[ -d "/etc/profiles/per-user/$USER/bin" ]]; then
            export PATH="/etc/profiles/per-user/$USER/bin:$PATH"
          fi
          if [[ -d "/run/wrappers/bin" ]]; then
            export PATH="/run/wrappers/bin:$PATH"
          fi
          if [[ -d "/run/current-system/sw/bin" ]]; then
            export PATH="/run/current-system/sw/bin:$PATH"
          fi

          # Color scheme exports — values sourced from lib/colors.nix
          export base00="${c.base00}"
          export base01="${c.base01}"
          export base02="${c.base02}"
          export base03="${c.base03}"
          export base04="${c.base04}"
          export base05="${c.base05}"
          export base06="${c.base06}"
          export base07="${c.base07}"
          export base08="${c.base08}"
          export base09="${c.base09}"
          export base0a="${c.base0A}"
          export base0b="${c.base0B}"
          export base0c="${c.base0C}"
          export base0d="${c.base0D}"
          export base0e="${c.base0E}"
          export base0f="${c.base0F}"
          export base10="${c.base10}"
          export base11="${c.base11}"
          export base12="${c.base12}"
          export base13="${c.base13}"
          export base14="${c.base14}"
          export base15="${c.base15}"
          export base16="${c.base16}"
          export base17="${c.base17}"
          export base8x0c="${c.extras.darkMidtone}"
          export blue="${c.base0C}"
          export green="${c.base0B}"
          export orange="${c.base09}"
          export purple="${c.base0D}"
          export red="${c.base08}"
          export yellow="${c.extras.yellowDim}"

          # Terminal and editor configuration
          export EDITOR="vim"
          export TERM="xterm-256color"
          export KITTY_TERM="kitty"

          # XDG directories (set only if not already defined)
          export XDG_BIN_HOME="''${XDG_BIN_HOME:-$HOME/.local/bin}"
          export XDG_CACHE_HOME="''${XDG_CACHE_HOME:-$HOME/.cache}"
          export XDG_CONFIG_HOME="''${XDG_CONFIG_HOME:-$HOME/.config}"
          export XDG_DATA_HOME="''${XDG_DATA_HOME:-$HOME/.local/share}"
          export XDG_LIB_HOME="''${XDG_LIB_HOME:-$HOME/.local/lib}"
          export XDG_STATE_HOME="''${XDG_STATE_HOME:-$HOME/.local/state}"
          export GOBIN="''${GOBIN:-$XDG_BIN_HOME}"
          export CLAUDE_CONFIG_DIR="''${XDG_CONFIG_HOME:-$HOME/.config}/claude"

          # Development environment
          export CAN_USE_SUDO=1
          export DOCKER_BUILDKIT=1
          export GOMPLATE_CONFIG="$XDG_CONFIG_HOME/gomplate/gomplate.yaml"

          # UI configuration
          export GUM_CHOOSE_CURSOR_FOREGROUND="$green"
          export GUM_CHOOSE_ITEM_FOREGROUND="$blue"
          export GUM_CHOOSE_SELECTED_FOREGROUND="$purple"
          export GUM_INPUT_CURSOR_FOREGROUND="$green"
          export GUM_INPUT_PLACEHOLDER="What is the value?"
          export GUM_INPUT_PROMPT="> "
          export GUM_INPUT_PROMPT_FOREGROUND="$blue"
          export GUM_INPUT_WIDTH=120
          export HAS_ALLOW_UNSAFE='y'

          # Homebrew configuration
          export HOMEBREW_NO_ANALYTICS=
          export HOMEBREW_NO_INSTALL_CLEANUP=true

          # Other tools
          export UNISON="$XDG_CONFIG_HOME/unison"
          export _ZO_DOCTOR=0

          # Ensure Homebrew is in PATH (important for GUI terminals)
      export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"

      # Ensure local user bin directory is available for tools like pipx
      export PATH="$XDG_BIN_HOME:$PATH"
    '';

    history = {
      save = 90000;
      size = 90000;
      expireDuplicatesFirst = true;
      ignoreAllDups = true;
    };
  };
}
