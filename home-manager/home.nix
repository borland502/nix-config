{ config, pkgs, lib, ... }:

{
  imports = [
    ./common.nix           # Import common configuration
    ./profiles/development.nix
    ./profiles/desktop.nix
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

  # Linux-specific Stylix targets (extending common.nix)
  stylix.targets = {
    kitty.enable = true;
    gtk.enable = true;
    kde.enable = true;
    qt.enable = false;
    firefox.enable = true;
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
        savePath = "/home/jhettenh/Pictures/Screenshots";
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
}
