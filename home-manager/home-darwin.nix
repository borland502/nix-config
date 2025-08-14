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
    jq
    yq

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
      monospace = [ "Fira Code Nerd Font Mono" ];
      sansSerif = [ "Inter" ];
      serif = [ "Liberation Serif" ];
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
  };

  # Direnv for automatic environment loading
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
  };

  # This value determines the home Manager release that your
  # configuration is compatible with.
  home.stateVersion = "25.05";

  # Let home Manager install and manage itself.
  programs.home-manager.enable = true;
}
