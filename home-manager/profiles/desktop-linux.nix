# Desktop-focused home-manager profile
{
  pkgs,
  lib,
  ...
}: let
  browserDesktopId = "vivaldi.desktop";
  desktopPackages = with pkgs; [
    # Web browsers
    firefox
    vivaldi

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

  availablePackages = lib.filter (pkg: lib.meta.availableOn pkgs.stdenv.hostPlatform pkg) desktopPackages;
in {
  # Desktop applications
  home.packages = availablePackages;
  home.sessionVariables.BROWSER = "vivaldi";

  # Note: System monitoring tools (htop, btop, iotop) moved to platform-specific configs
  # Note: Removed duplicated discord entry

  xdg = {
    desktopEntries.vivaldi = {
      name = "Vivaldi";
      genericName = "Web Browser";
      exec = "${pkgs.vivaldi}/bin/vivaldi %U";
      terminal = false;
      categories = ["Network" "WebBrowser"];
      mimeType = [
        "application/xhtml+xml"
        "text/html"
        "x-scheme-handler/about"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
        "x-scheme-handler/unknown"
      ];
    };

    mimeApps = {
      enable = true;
      defaultApplications = {
        "application/xhtml+xml" = [browserDesktopId];
        "text/html" = [browserDesktopId];
        "x-scheme-handler/about" = [browserDesktopId];
        "x-scheme-handler/http" = [browserDesktopId];
        "x-scheme-handler/https" = [browserDesktopId];
        "x-scheme-handler/unknown" = [browserDesktopId];
      };
    };
  };

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
