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

      # Default terminal (KDE's "open terminal here", Ctrl+Alt+T targets, etc.).
      configFile.kdeglobals.General = {
        TerminalApplication = "kitty";
        TerminalService = "kitty.desktop";
      };

      # Input — sensible laptop defaults (live config was all-default). Touchpad
      # tap-to-click, natural scroll, disable-while-typing. numlockOnStartup was
      # intentionally dropped: it perturbs password entry (numpad digits), the
      # live config left it at the default, and it was implicated in the greeter
      # login-failure incident.
      input = {
        touchpads = [
          {
            name = "DELL0A69:00 0488:120A Touchpad";
            vendorId = "0488";
            productId = "120A";
            enable = true;
            tapToClick = true;
            naturalScroll = true;
            disableWhileTyping = true;
          }
        ];
      };

      # Power management (captured from the live powerdevilrc). On AC: blank the
      # display after 30 min, auto-suspend after 2 h, do nothing on lid close
      # (docked use). On battery: power button shuts down.
      powerdevil = {
        AC = {
          turnOffDisplay.idleTimeout = 1800;
          autoSuspend.idleTimeout = 7200;
          whenLaptopLidClosed = "doNothing";
        };
        battery.powerButtonAction = "shutDown";
      };

      # Screen locker — auto-lock after 30 min (matches the live setting).
      kscreenlocker = {
        autoLock = true;
        timeout = 30;
      };

      # Bottom panel, captured from the live layout so it is reproducible.
      # NOTE: applying this deletes and regenerates
      # plasma-org.kde.plasma.desktop-appletsrc on next login (plasma-manager
      # avoids unbounded growth this way). The desktop is all-default (Folder
      # View, empty icon positions, Stylix wallpaper), so nothing is lost there;
      # only this panel needs declaring. The icontasks launchers below preserve
      # the pinned taskbar entries that would otherwise reset.
      panels = [
        {
          location = "bottom";
          widgets = [
            "org.kde.plasma.kickoff"
            "org.kde.plasma.pager"
            {
              iconTasks.launchers = [
                "preferred://filemanager"
                "applications:kitty.desktop"
                "applications:com.slack.Slack.desktop"
                "applications:org.kde.kmail2.desktop"
                "applications:com.vivaldi.Vivaldi.desktop"
                "applications:org.keepassxc.KeePassXC.desktop"
                "applications:code.desktop"
              ];
            }
            "org.kde.plasma.marginsseparator"
            "org.kde.plasma.systemtray"
            "org.kde.plasma.digitalclock"
            "org.kde.plasma.showdesktop"
          ];
        }
      ];
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
