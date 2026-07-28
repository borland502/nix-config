# Desktop-focused home-manager profile
{
  pkgs,
  lib,
  ...
}: let
  # Use Vivaldi's own shipped desktop file. Vivaldi's binary self-checks the
  # default browser against a hardcoded "vivaldi-stable.desktop"; pointing the
  # default at any other id (e.g. a custom vivaldi.desktop) makes Vivaldi think
  # it isn't the default and prompt on every launch. The nixpkgs package ships
  # vivaldi-stable.desktop with Exec wired to the Nix binary.
  browserDesktopId = "vivaldi-stable.desktop";
  mailDesktopId = "thunderbird.desktop";

  desktopPackages = with pkgs; [
    # Web browsers
    firefox
    vivaldi

    # Media
    vlc
    mpv

    # Communication
    discord
    zoom-us

    # Productivity
    libreoffice
    obsidian

    # Graphics and design
    gimp
    inkscape

    # GUI tools
    # kitty: intentionally NOT Nix-managed here (see chezmoi/dot_config/kitty
    # for its config, still theming-managed via stylix.targets.kitty). A
    # Nix-built kitty is linked against Nix's own glibc; on this hybrid
    # Intel/NVIDIA CachyOS host it cannot safely load either GPU vendor's
    # driver .so (loading them pulls in the host's glibc into the same
    # process and hits a `GLIBC_PRIVATE` symbol clash), so it segfaults on
    # every launch regardless of Wayland/EGL vs X11/GLX backend. Installed
    # instead via the host package manager: `pkg-install kitty`.
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
    # Keep /etc/xdg in XDG_CONFIG_DIRS. This is a standalone Home Manager host
    # (non-NixOS CachyOS), so /etc/xdg is only XDG's *implicit* default when the
    # variable is unset. Stylix's KDE target sets XDG_CONFIG_DIRS explicitly (via
    # xdg.systemDirs.config, adding its generated stylix-kde-config path), which
    # replaces that implicit default — and since the systemd user session starts
    # with XDG_CONFIG_DIRS empty, the `${XDG_CONFIG_DIRS:+…}` append leaves
    # /etc/xdg out entirely. Without it KDE's VFolderMenu can't find
    # /etc/xdg/menus/plasma-applications.menu, so no application directories are
    # scanned: the KService database ends up empty, and the Kickoff launcher and
    # taskbar show no applications (though apps still launch directly). mkAfter
    # appends /etc/xdg *after* the stylix entry so theme config keeps precedence.
    # (On NixOS the system provides /etc/xdg here, so this is only needed on
    # foreign distros.)
    systemDirs.config = lib.mkAfter ["/etc/xdg"];

    # No custom desktopEntries.vivaldi: the nixpkgs vivaldi package already
    # ships vivaldi-stable.desktop (Exec wired to the Nix binary), which is the
    # id Vivaldi self-checks against. A second vivaldi.desktop only shadows it
    # and re-triggers the "set as default" prompt.

    mimeApps = {
      enable = true;
      defaultApplications = {
        "application/xhtml+xml" = [browserDesktopId];
        "text/html" = [browserDesktopId];
        "x-scheme-handler/about" = [browserDesktopId];
        "x-scheme-handler/http" = [browserDesktopId];
        "x-scheme-handler/https" = [browserDesktopId];
        "x-scheme-handler/unknown" = [browserDesktopId];

        # Thunderbird: email
        "x-scheme-handler/mailto" = [mailDesktopId];
        "message/rfc822" = [mailDesktopId];
        # Thunderbird: calendar (ics files + webcal subscription links)
        "text/calendar" = [mailDesktopId];
        "x-scheme-handler/webcal" = [mailDesktopId];
        "x-scheme-handler/webcals" = [mailDesktopId];
        # Thunderbird: protocol-scheme links (message-id, news/usenet)
        "x-scheme-handler/mid" = [mailDesktopId];
        "x-scheme-handler/news" = [mailDesktopId];
        "x-scheme-handler/snews" = [mailDesktopId];
        "x-scheme-handler/nntp" = [mailDesktopId];
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
