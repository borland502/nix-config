{
  config,
  pkgs,
  lib,
  ...
}: let
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
in {
  _module.args.isWsl = lib.mkDefault false;

  imports = [
    ./common.nix # Import common configuration
    ./profiles/development-linux.nix
    ./profiles/desktop-linux.nix
  ];

  home = {
    username = lib.mkDefault "jhettenh";
    homeDirectory = lib.mkDefault "/home/jhettenh";

    # Linux-specific packages
    packages = availableLinuxPackages;
  };

  # Linux-specific Stylix targets
  stylix.targets = {
    kitty.enable = true;
    gtk.enable = true;
    kde.enable = true;
    firefox = {
      enable = true;
      profileNames = ["default"];
    };
  };

  # Linux-specific font fallbacks
  fonts.fontconfig.defaultFonts = {
    sansSerif = lib.mkAfter ["DejaVu Sans"];
    serif = lib.mkAfter ["DejaVu Serif"];
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

  # Flameshot rewrites its own flameshot.ini at runtime (adding [Shortcuts]
  # etc.), turning the HM-managed symlink into a real file. Without force, the
  # next switch tries to back it up to flameshot.ini.backup and fails once that
  # backup already exists. Let HM win outright: overwrite in place, no backup.
  # (darwin instead seeds a mutable copy — see home-darwin.nix.)
  xdg.configFile."flameshot/flameshot.ini".force = true;

  # GTK2 apps rewrite ~/.gtkrc-2.0 at runtime, replacing the Stylix-managed
  # symlink with a real file. Same failure mode as flameshot above: the next
  # switch's `-b backup` collides with an existing .gtkrc-2.0.backup. Force HM
  # (Stylix) to overwrite in place without a backup. Key by the gtk module's
  # own configLocation so this merges with its entry instead of colliding.
  home.file.${config.gtk.gtk2.configLocation}.force = lib.mkForce true;

  # flameshot uses savePathFixed=true, so it errors if the configured savePath
  # does not already exist. Ensure the screenshot directory is present.
  home.activation.ensureFlameshotSavePath = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${pkgs.coreutils}/bin/mkdir -p "${config.home.homeDirectory}/Pictures/Screenshots"
  '';

  # Autostart GUI apps via systemd user services
  systemd.user.services =
    lib.optionalAttrs (availableOnHost pkgs.discord) {
      discord = {
        Unit = {
          Description = "Start Discord on graphical session";
          PartOf = ["graphical-session.target"];
          After = ["graphical-session-pre.target"];
        };
        Service = {
          ExecStart = "${pkgs.discord}/bin/discord";
          Restart = "on-failure";
          RestartSec = 5;
        };
        Install = {WantedBy = ["graphical-session.target"];};
      };
    }
    // lib.optionalAttrs (availableOnHost pkgs.slack) {
      slack = {
        Unit = {
          Description = "Start Slack on graphical session";
          PartOf = ["graphical-session.target"];
          After = ["graphical-session-pre.target"];
        };
        Service = {
          ExecStart = "${pkgs.slack}/bin/slack";
          Restart = "on-failure";
          RestartSec = 5;
        };
        Install = {WantedBy = ["graphical-session.target"];};
      };
    };

  programs = {
    # Linux-specific KDE shortcuts
    plasma = {
      enable = true;
      shortcuts = {
        # Unbind flameshot's built-in "Capture" global shortcut; the capture
        # modes are bound as explicit command hotkeys below (more reliable on
        # Wayland and lets each mode get its own key).
        "flameshot" = {
          "Capture" = [];
        };
      };

      # Flameshot capture hotkeys, macOS-style: Alt+Shift+{3,4,5}.
      hotkeys.commands = {
        "flameshot-full" = {
          name = "Flameshot: capture all screens";
          key = "Alt+Shift+3";
          command = "${pkgs.flameshot}/bin/flameshot full";
        };
        "flameshot-region" = {
          name = "Flameshot: region capture";
          key = "Alt+Shift+4";
          command = "${pkgs.flameshot}/bin/flameshot gui";
        };
        "flameshot-launcher" = {
          name = "Flameshot: capture launcher";
          key = "Alt+Shift+5";
          command = "${pkgs.flameshot}/bin/flameshot launcher";
        };
      };

      # Disable Plasma "hot corners" — the corner-triggered screen-edge
      # actions. Plasma 6 enables top-left -> Overview by default; the other
      # corners are already inert but are pinned to "no action" so nothing
      # fires when the pointer hits a corner. KWin ElectricBorder value
      # 9 = ElectricNone (disabled); "None" is the ElectricBorders action.
      configFile.kwinrc = {
        "Effect-overview".BorderActivate = 9;
        "Effect-overview".BorderActivateAll = 9;
        "Effect-windowview".BorderActivate = 9;
        "Effect-windowview".BorderActivateAll = 9;
        "Effect-windowview".BorderActivateClass = 9;
        ElectricBorders.TopLeft = "None";
        ElectricBorders.TopRight = "None";
        ElectricBorders.BottomLeft = "None";
        ElectricBorders.BottomRight = "None";
      };
    };

    # Thunderbird configuration
    thunderbird = {
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

    bash = {
      enable = true;
      enableCompletion = true;
    };
  };
}
