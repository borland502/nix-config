# Desktop-focused home-manager profile
{ config, pkgs, ... }:

{
  # Desktop applications
  home.packages = with pkgs; [
    # Web browsers
    firefox
    
    # Media
    vlc
    mpv
    
    # Communication
    discord
    
    # Productivity
    libreoffice
    obsidian
    
    # Graphics and design
    gimp
    inkscape
    
    # GUI tools
    flameshot
    slack
    keepassxc    
  ];

  # Note: System monitoring tools (htop, btop, iotop) moved to platform-specific configs
  # Note: Removed duplicated discord entry

  # Firefox configuration
  programs.firefox = {
    enable = true;
    profiles.default = {
      name = "Default";
      isDefault = true;
      settings = {
        "browser.startup.homepage" = "https://dashy.technohouser.com";
        "privacy.trackingprotection.enabled" = true;
        "dom.security.https_only_mode" = true;
      };
    };
  };
}
