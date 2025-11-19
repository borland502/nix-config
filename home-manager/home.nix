{ config, pkgs, lib, ... }:

let
  linuxPackages = with pkgs; [
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
    dbus
  ];

  availableOnHost = pkg: lib.meta.availableOn pkgs.stdenv.hostPlatform pkg;
  availableLinuxPackages = lib.filter availableOnHost linuxPackages;
in
{
  imports = [
    ./common.nix           # Import common configuration
    ./profiles/development-linux.nix
    ./profiles/desktop-linux.nix
  ];

  home.username = lib.mkDefault "jhettenh";
  home.homeDirectory = lib.mkDefault "/home/jhettenh";

  # Linux-specific packages
  home.packages = availableLinuxPackages;

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
        savePath = "${config.home.homeDirectory}/Pictures/Screenshots";
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
  systemd.user.services =
    lib.optionalAttrs (availableOnHost pkgs.discord) {
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
    }
    // lib.optionalAttrs (availableOnHost pkgs.slack) {
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

  programs.bash = {
    enable = true;
    enableCompletion = true;
    profileExtra = ''
      if [ -n "$INSIDE_DEVCONTAINER" ] && [ -z "$BASH_NO_AUTO_ZSH" ] && [ -t 0 ] && command -v zsh >/dev/null 2>&1; then
        exec zsh -l
      fi
    '';
    initExtra = ''
      if [ -n "$INSIDE_DEVCONTAINER" ] && [ -z "$BASH_NO_AUTO_ZSH" ] && [ -t 0 ] && command -v zsh >/dev/null 2>&1; then
        exec zsh
      fi
    '';
  };
}
