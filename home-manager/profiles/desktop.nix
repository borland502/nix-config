# Desktop-focused home-manager profile
{ config, pkgs, ... }:

{
  # Desktop applications
  home.packages = with pkgs; [
    # Web browsers
    firefox
    chromium
    
    # Media
    vlc
    mpv
    spotify
    
    # Communication
    discord
    telegram-desktop
    
    # Productivity
    libreoffice
    obsidian
    
    # Graphics and design
    gimp
    inkscape
    
    # Utilities
    filelight
    spectacle
    ark
    
    # System monitoring
    htop
    btop
    iotop
  ];

  # Firefox configuration
  programs.firefox = {
    enable = true;
    profiles.default = {
      name = "Default";
      isDefault = true;
      settings = {
        "browser.startup.homepage" = "https://start.duckduckgo.com";
        "privacy.trackingprotection.enabled" = true;
        "dom.security.https_only_mode" = true;
      };
    };
  };
}
