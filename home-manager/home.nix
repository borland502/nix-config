{ config, pkgs, lib, ... }:

{
  imports = [
    ./profiles/development.nix
    ./profiles/desktop.nix
    ./zsh.nix
    ./starship.nix
  ];

  home.username = "jhettenh";
  home.homeDirectory = lib.mkForce "/home/jhettenh";

  # Core packages not covered by profiles
  home.packages = with pkgs; [
    # System monitoring and utilities
    btop
    iotop
    iftop
    strace
    ltrace
    lsof
    sysstat
    lm_sensors
    ethtool
    pciutils
    usbutils

    # Development tools
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
        "Fira Sans Nerd Font" 
        "Inter"
        "DejaVu Sans"
      ];
      serif = [ 
        "Liberation Serif" 
        "DejaVu Serif"
        "Times"
      ];
    };
  };

  # Basic program configurations
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
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.jq.enable = true;
  programs.rclone.enable = true;

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  # Plasma configuration
  programs.plasma = {
    enable = true;
    workspace = {
      lookAndFeel = "org.kde.breezedark.desktop"; 
      colorScheme = "BreezeDark"; 
      theme = "breeze-dark";
    };
    shortcuts = {
      "flameshot" = {
        "Capture" = "Ctrl+Shift+S";
      };
    };
  };

  # Services
  services.flameshot = {
    enable = true;
    settings = {
      General = {
        disabledTrayIcon = false;
        showStartupLaunchMessage = false;
        savePath = "/home/jhettenh/Pictures/Screenshots";
        savePathFixed = true;
      };
    };
  };

  # Styling with Stylix
  stylix = {
    enable = true;
    base16Scheme = ./config/colors/monokai.base24.yaml;
    targets = {
      kitty.enable = true;
      starship.enable = true;
      bat.enable = true;
      gtk.enable = true;
      kde.enable = true;
      qt.enable = false;
      vim.enable = true;
      firefox.profileNames = ["default"];
    };
    polarity = "dark";
  };

  # This value determines the home Manager release that your
  # configuration is compatible with.
  home.stateVersion = "25.05";

  # Let home Manager install and manage itself.
  programs.home-manager.enable = true;
}
