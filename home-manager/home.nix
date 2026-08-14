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

  # False here so standalone home-manager on a generic Linux distro (CachyOS on
  # Tifa) never installs the GPU-dependent packages guarded in
  # profiles/desktop-linux.nix. The NixOS host overrides this to true in
  # flake.nix, where /run/opengl-driver exists and those packages work.
  _module.args.isNixos = lib.mkDefault false;

  imports = [
    ./common.nix # Import common configuration
    ./profiles/development-linux.nix
    ./profiles/desktop-linux.nix
    ./modules/gdrive-sync.nix # daily systemd timer for sync-to-gdrive
    ./modules/vscode-profiles.nix # language profiles, shared with darwin
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

  # GTK3 never sees the desktop's dark preference. `color-scheme=prefer-dark`
  # (gsettings, republished by the XDG portal as org.freedesktop.appearance)
  # is read by GTK4/libadwaita only — GTK3 consults this settings.ini key
  # alone, and stylix's gtk target does not set it. The result was GTK3 apps
  # loading the light adw-gtk3 stylesheet on a dark desktop while GTK4 apps
  # rendered dark. adw-gtk3 ships share/themes/adw-gtk3/gtk-3.0/gtk-dark.css,
  # so this flips GTK3 to the dark sheet without touching the theme *name*
  # (adw-gtk3), which stylix owns. GTK4 dropped the property, so it is set for
  # gtk3 only.
  gtk.gtk3.extraConfig.gtk-application-prefer-dark-theme = true;

  # Linux-specific font fallbacks
  fonts.fontconfig.defaultFonts = {
    sansSerif = lib.mkAfter ["DejaVu Sans"];
    serif = lib.mkAfter ["DejaVu Serif"];
  };

  # Screenshots on Linux go through Spectacle, not Flameshot. Flameshot cannot
  # capture on a KWin/Wayland session at all: the nixpkgs wrapper delegates
  # Wayland capture to grim, which speaks the wlroots-only wlr-screencopy
  # protocol that KWin does not implement (`grim` exits with "compositor
  # doesn't support the screen capture protocol"), and flameshot's non-grim
  # DBus path never reaches xdg-desktop-portal either. Both modes fail with
  # "Unable to capture screen". Darwin keeps Flameshot — see home-darwin.nix.
  #
  # Spectacle is intentionally NOT installed via nix here. KWin's
  # org.kde.KWin.ScreenShot2 authorizes callers by executable path, and it
  # trusts the spectacle shipped alongside the running KWin. A nix-store
  # spectacle is rejected outright ("The process is not authorized to take a
  # screenshot"), so the hotkeys below invoke a bare `spectacle` resolved from
  # PATH: the distro binary on this Plasma host, the nix one on NixOS. Adding
  # kdePackages.spectacle to home.packages would shadow /usr/bin/spectacle and
  # break capture on non-NixOS hosts.

  # Kitty terminal configuration. chezmoi ignores .config/kitty/kitty.conf on
  # every non-Windows platform (its source here is the base only) on the
  # assumption that home-manager deploys the merged file — darwin already
  # does this (home-darwin.nix); this is the Linux equivalent, so the file
  # actually lands (previously it did not exist on disk at all here, leaving
  # kitty on factory defaults — small window, no font, no theme).
  xdg.configFile."kitty/kitty.conf".text = let
    c = import ./lib/colors.nix;
    baseCfg = builtins.readFile ../chezmoi/dot_config/kitty/kitty.conf;
  in
    baseCfg
    + ''

      # Theme: Monokai Spectrumish
      # Source: chezmoi/dot_config/colors/monokai.toml
      foreground ${c.base05}
      background ${c.base00}
      cursor     ${c.base05}

      color0  ${c.base00}
      color8  ${c.base03}
      color1  ${c.base08}
      color9  ${c.base12}
      color2  ${c.base0B}
      color10 ${c.base14}
      color3  ${c.base0A}
      color11 ${c.base13}
      color4  ${c.base0D}
      color12 ${c.base16}
      color5  ${c.base0E}
      color13 ${c.base0E}
      color6  ${c.base0C}
      color14 ${c.base15}
      color7  ${c.base05}
      color15 ${c.base07}
    '';

  # GTK2 apps rewrite ~/.gtkrc-2.0 at runtime, replacing the Stylix-managed
  # symlink with a real file. The next switch's `-b backup` then collides with
  # an existing .gtkrc-2.0.backup. Force HM (Stylix) to overwrite in place
  # without a backup. Key by the gtk module's own configLocation so this merges
  # with its entry instead of colliding.
  home.file.${config.gtk.gtk2.configLocation}.force = lib.mkForce true;

  # Spectacle saves to <Pictures>/Screenshots by default (its spectaclerc
  # `translatedScreenshotsFolder`). spectaclerc itself is deliberately left
  # unmanaged — Spectacle rewrites it at runtime, which is the same
  # symlink-clobber trap as .gtkrc-2.0 above. Just guarantee the directory.
  home.activation.ensureScreenshotSavePath = lib.hm.dag.entryAfter ["writeBoundary"] ''
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
        # Spectacle's .desktop file claims Print (and Meta+Shift+Print etc.)
        # by default. Leave those alone; the macOS-style keys below are added
        # alongside them as explicit command hotkeys, one per capture mode.

        # Konsole's own .desktop file declares X-KDE-Shortcuts=Ctrl+Alt+T,
        # which kglobalaccel auto-registers the first time it scans services
        # — independent of (and not overridden by) the TerminalApplication/
        # TerminalService default-terminal settings below. kitty's .desktop
        # file declares no such key, so it never contests the binding.
        # Reassign explicitly: clear Konsole's claim, give it to kitty.
        "org.kde.konsole.desktop" = {
          "_launch" = [];
        };
        "kitty.desktop" = {
          "_launch" = "Ctrl+Alt+T";
        };
      };

      # Spectacle capture hotkeys, macOS-style: Alt+Shift+{3,4,5}.
      # Bare `spectacle` on purpose — see the ScreenShot2 authorization note
      # above; an absolute nix-store path is rejected by KWin.
      hotkeys.commands = {
        "spectacle-full" = {
          name = "Spectacle: capture all screens";
          key = "Alt+Shift+3";
          command = "spectacle -f -b";
        };
        "spectacle-region" = {
          name = "Spectacle: region capture";
          key = "Alt+Shift+4";
          command = "spectacle -r -b";
        };
        "spectacle-launcher" = {
          name = "Spectacle: capture launcher";
          key = "Alt+Shift+5";
          command = "spectacle -l";
        };
      };

      # Four virtual desktops in a single row, so Meta+Ctrl+Left/Right walks
      # the whole set (Plasma ships with one desktop, which makes the stock
      # switching shortcuts no-ops). Names are left unset: without them KWin
      # labels the desktops "Desktop 1".."Desktop 4", which is what the
      # pager and the switcher OSD would show anyway.
      kwin.virtualDesktops = {
        number = 4;
        rows = 1;
      };

      # Disable Plasma "hot corners" — the corner-triggered screen-edge
      # actions. Plasma 6 enables top-left -> Overview by default; the other
      # corners are already inert but are pinned to "no action" so nothing
      # fires when the pointer hits a corner. KWin ElectricBorder value
      # 9 = ElectricNone (disabled); "None" is the ElectricBorders action.
      configFile.kwinrc = {
        "Effect-overview" = {
          BorderActivate = 9;
          BorderActivateAll = 9;
        };
        "Effect-windowview" = {
          BorderActivate = 9;
          BorderActivateAll = 9;
          BorderActivateClass = 9;
        };
        ElectricBorders = {
          TopLeft = "None";
          TopRight = "None";
          BottomLeft = "None";
          BottomRight = "None";
        };
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
          # Pin the panel to screen 0 (the primary external display). Without
          # this, re-applying the layout recreates the panel wherever Plasma
          # feels like putting it — it landed on the laptop's internal eDP
          # panel, not the monitor it had always been on.
          screen = 0;
          widgets = [
            "org.kde.plasma.kickoff"
            "org.kde.plasma.pager"
            {
              # Desktop IDs must match the .desktop files actually installed on
              # this Nix host, or plasmashell prunes the unresolvable launcher
              # from the panel on next start (icontasks silently drops pins whose
              # service KService can't resolve). Re-synced from the live panel
              # (plasma-org.kde.plasma.desktop-appletsrc) on 2026-07-27.
              #
              # Spelled as concrete "applications:" ids rather than
              # "preferred://" wherever the app is pinned by name anyway. A
              # preferred:// entry resolves through the mimeapps association and
              # degrades badly when that is missing: it stays in the panel as a
              # blank generic icon that launches nothing, rather than being
              # pruned. filemanager hit exactly that (no inode/directory default
              # was declared); it now has one in mimeapps/defaults.toml, and the
              # pin no longer depends on it either way.
              iconTasks.launchers = [
                "applications:systemsettings.desktop"
                "applications:org.kde.dolphin.desktop"
                "applications:code.desktop"
                "preferred://browser"
                "applications:kitty.desktop"
                "applications:steam.desktop"
                "applications:org.keepassxc.KeePassXC.desktop"
                "applications:slack.desktop"
                "applications:discord.desktop"
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
