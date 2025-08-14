# Common home-manager configuration shared between Linux and Darwin
{ config, pkgs, lib, ... }:

{
  # Shared imports
  imports = [
    ./zsh.nix
    ./starship.nix
  ];

  # Common packages (platform-agnostic)
  home.packages = with pkgs; [
    # Development tools
    git
    gh
    curl
    wget
    go-task

    # Shell integration tools
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

    # System monitoring (cross-platform)
    btop
    lsof
  ];

  # Common font configuration
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
        "DejaVu Sans"
      ];
      serif = [ 
        "Liberation Serif" 
        "Times New Roman"
        "Times"
        "DejaVu Serif"
      ];
    };
  };

  # Common Stylix configuration
  stylix = {
    enable = true;
    base16Scheme = ./config/colors/monokai.base24.yaml;
    
    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.fira-code;
        name = "FiraCode Nerd Font Mono";
      };
      sansSerif = {
        package = pkgs.inter;
        name = "Inter";
      };
      serif = {
        package = pkgs.liberation_ttf;
        name = "Liberation Serif";
      };
    };

    # Common theming targets
    targets = {
      bat.enable = true;
      fzf.enable = true;
      vim.enable = true;
      btop.enable = true;
    };
  };

  # Common Git configuration
  programs.git = {
    enable = true;
    userName = "jhettenh";
    userEmail = "jhettenh@example.com";
    extraConfig = {
      init.defaultBranch = "main";
      core.editor = "vim";
      pull.rebase = false;
    };
  };

  # Common program configurations
  programs.bat.enable = true;
  programs.dircolors = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.eza = {
    enable = true;
    enableZshIntegration = true;
    colors = "always";
    git = true;
    icons = "always";
  };

  programs.fd.enable = true;
  programs.ripgrep.enable = true;

  # Direnv for automatic environment loading
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
  };

  # Common home-manager settings
  home.stateVersion = "25.05";
  programs.home-manager.enable = true;
}
