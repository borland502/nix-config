{ config, pkgs, lib, ... }:

{
  imports = [
    # ./profiles/development.nix  # Temporarily disabled to avoid VSCode unfree issue
    ./zsh.nix
    ./starship.nix
  ];

  home.username = "jhettenh";
  home.homeDirectory = lib.mkForce "/Users/jhettenh";

  # Core packages not covered by profiles
  home.packages = with pkgs; [
    # System monitoring and utilities (macOS compatible)
    btop
    # Note: iotop removed as it's Linux-only
    lsof

    # Development tools
    git
    gh
    curl
    wget
    go-task

    # Shell integration tools (moved from global)
    bat        # Better cat with syntax highlighting
    eza        # Modern ls replacement
    fzf        # Fuzzy finder
    fd         # Better find
    ripgrep    # Fast text search
    sd         # Better sed
    jq         # JSON processor
    yq         # YAML processor
    zoxide     # Smart cd replacement

    # Productivity and content
    hugo
    glow
    gum
    nix-output-monitor
    tealdeer

    # Basic utilities
    cowsay
    file
    which
    tree
    ncdu
    rsync
    direnv

    # macOS-specific GUI applications
    firefox
    # Note: Many GUI apps on macOS are better installed via Homebrew or App Store
  ];

  # Font configuration
  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      monospace = [ 
        "FiraCode Nerd Font Mono"
        "FiraCode Nerd Font" 
        "Fira Code"
        "JetBrainsMono Nerd Font"
        "Source Code Pro"
      ];
      sansSerif = [ 
        "FiraCode Nerd Font Propo"
        "Inter" 
        "Helvetica"
        "Arial"
      ];
      serif = [ 
        "Liberation Serif" 
        "Times New Roman"
        "Times"
      ];
    };
  };

  # Git configuration
  programs.git = {
    enable = true;
    userName = "jhettenh";
    userEmail = "jhettenh@example.com";
    extraConfig = {
      init.defaultBranch = "main";
      core.editor = "vim";  # Changed from code to vim to avoid VSCode dependency
      pull.rebase = false;
    };
  };

  # Shell configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    initContent = ''
      # Ensure home-manager packages are in PATH
      export PATH="$HOME/.local/state/nix/profiles/home-manager/home-path/bin:$PATH"
      
      # Ensure Homebrew is in PATH (critical for GUI terminals like kitty)
      export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
      
      # Disable loading of old zsh configurations that might conflict
      # This prevents zmodule errors from old Zim framework
      unset ZIM_HOME
      unset ZIM_CONFIG_FILE
    '';
  };

    # Direnv for automatic environment loading
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
  };

  # Kitty terminal configuration
  xdg.configFile."kitty/kitty.conf".source = ./config/kitty/kitty.conf;

  # VSCode configuration for font consistency
  xdg.configFile."Code/User/settings.json".source = ./config/vscode/settings.json;

  # This value determines the home Manager release that your
  # configuration is compatible with. This helps avoid breakage

  # This value determines the home Manager release that your
  # configuration is compatible with.
  home.stateVersion = "25.05";

  # Let home Manager install and manage itself.
  programs.home-manager.enable = true;
}
