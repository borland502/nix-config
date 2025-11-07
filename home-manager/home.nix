{ config, pkgs, lib, ... }:

{
  imports = [
    ./common.nix           # Import common configuration
    ./profiles/development-linux.nix
    ./profiles/desktop-linux.nix
  ];

  home.username = "jhettenh";
  home.homeDirectory = lib.mkForce "/home/jhettenh";

  # Linux-specific packages
  home.packages = with pkgs; [
    # Linux-specific system monitoring
    iotop
    iftop
    strace
    ltrace
    sysstat
    lm_sensors
    ethtool
    pciutils
    usbutils
  ];

  # Linux-specific Stylix targets
  stylix.targets = {
    kitty.enable = true;
    gtk.enable = true;
    kde.enable = true;
    firefox = {
      enable = true;
      profileNames = [ "default" ];
    };
  };

  # Linux-specific font fallbacks
  fonts.fontconfig.defaultFonts = {
    sansSerif = lib.mkAfter [ "DejaVu Sans" ];
    serif = lib.mkAfter [ "DejaVu Serif" ];
  };

  # Linux-specific services
  services.flameshot = {
    enable = true;
    settings = {
      General = {
        disabledTrayIcon = false;
        showStartupLaunchMessage = false;
        savePath = "/home/42245/Pictures/Screenshots";
        savePathFixed = true;
      };
    };
  };

  # Linux-specific KDE shortcuts
  programs.plasma = {
    enable = true;
    shortcuts = {
      "flameshot" = {
        "Capture" = "Ctrl+Shift+S";
      };
    };
  };

  # Autostart GUI apps via systemd user services
  systemd.user.services = {
    discord = {
      Unit = {
        Description = "Start Discord on graphical session";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session-pre.target" ];
      };
      Service = {
        ExecStart = "${pkgs.discord}/bin/discord";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install = { WantedBy = [ "graphical-session.target" ]; };
    };

    slack = {
      Unit = {
        Description = "Start Slack on graphical session";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session-pre.target" ];
      };
      Service = {
        ExecStart = "${pkgs.slack}/bin/slack";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install = { WantedBy = [ "graphical-session.target" ]; };
    };
  };

  # Thunderbird configuration
  programs.thunderbird = {
    enable = true;
    package = pkgs.thunderbird;
    profiles.default = {
      isDefault = true;
      settings = {
        # UI/appearance
        "ui.systemUsesDarkTheme" = 1;
        "svg.context-properties.content.enabled" = true;
        # Behavior
        "mail.spellcheck.inline" = true;
        "mailnews.start_page.enabled" = false;
        "mailnews.default_sort_type" = 18; # sort by date desc
        # Performance/UX
        "general.smoothScroll" = true;
        # Allow userChrome.css if you want to theme further later
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      };
    };
  };
}
