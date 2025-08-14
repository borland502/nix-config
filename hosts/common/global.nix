# Common configuration shared across all hosts
{ config, lib, pkgs, ... }:

{
  # Common settings for all hosts
  time.timeZone = "America/New_York";
  
  # Internationalization
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Networking
  networking.networkmanager.enable = true;
  networking.useDHCP = lib.mkDefault true;

  # Boot configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Shell configuration
  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;

  # Security
  security.sudo.wheelNeedsPassword = false;

  # Nix configuration
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreePredicate = (_: true);
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Essential system packages (core system tools only)
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    curl
    htop
    tree
    unzip
    rclone
    # Shell integration tools moved to home-manager configurations
    # - bat, eza, fzf, fd, ripgrep, sd, jq, zoxide
  ];

  environment.shells = with pkgs; [
    zsh
    bash
  ];

  # System-wide font configuration
  fonts.packages = with pkgs; [
    # Fira Code Nerd Font variants
    nerd-fonts.fira-code
    nerd-fonts.fira-mono
    
    # Additional programming fonts
    nerd-fonts.jetbrains-mono
    nerd-fonts.source-code-pro
    
    # System fonts
    liberation_ttf
  ];

  # Common services
  services.openssh.enable = true;
  services.printing.enable = true;
}
