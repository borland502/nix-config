{ config, pkgs, lib, ... }:

{
  imports = [
    ./profiles/development.nix
    ./profiles/desktop.nix
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
  ];

  # Font configuration
  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      monospace = [ "Fira Code Nerd Font Mono" ];
      sansSerif = [ "Fira Sans Nerd Font" ];
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

  # Zsh configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    
    shellAliases = {
      ll = "ls -l";
      la = "ls -la";
      grep = "grep --color=auto";
    };
  };

  # Starship prompt
  programs.starship = {
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
  };

  # Services
  services.kdeconnect = {
    enable = true;
    indicator = true;
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
