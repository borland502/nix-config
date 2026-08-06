# Desktop-focused home-manager profile
{
  pkgs,
  lib,
  isNixos ? false,
  ...
}: let
  # Use Vivaldi's own shipped desktop file. Vivaldi's binary self-checks the
  # default browser against a hardcoded "vivaldi-stable.desktop"; pointing the
  # default at any other id (e.g. a custom vivaldi.desktop) makes Vivaldi think
  # it isn't the default and prompt on every launch. The nixpkgs package ships
  # vivaldi-stable.desktop with Exec wired to the Nix binary.
  browserDesktopId = "vivaldi-stable.desktop";
  mailDesktopId = "thunderbird.desktop";

  # Zoom's meeting links must open whichever Zoom actually exists on the host.
  # nixpkgs zoom-us ships "Zoom.desktop"; the Flathub build used on generic
  # Linux (see nixosOnlyPackages) ships "us.zoom.Zoom.desktop". Declaring this
  # explicitly matters because mimeapps.list is a read-only symlink into the
  # store here, so `xdg-mime default` cannot repair a wrong association after
  # the fact.
  zoomDesktopId =
    if isNixos
    then "Zoom.desktop"
    else "us.zoom.Zoom.desktop";

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
    # kitty and zoom-us are GPU-dependent and live in nixosOnlyPackages below.
    flameshot
    slack
    keepassxc
  ];

  # GPU-dependent apps that only work when Nix also owns the graphics stack.
  #
  # A Nix-built GL application resolves drivers through /run/opengl-driver,
  # which only exists on NixOS (populated by hardware.graphics). On a generic
  # Linux host that path is absent and there is no nixGL here, so:
  #
  #   * zoom-us fails GLX/EGL init and Qt aborts the process. Observed on Tifa
  #     (CachyOS) as SIGABRT in libQt6Core on every launch, with
  #     "MESA-LOADER: failed to open dri: /run/opengl-driver/lib/gbm/dri_gbm.so"
  #     in ~/.zoom/logs/zoom_stdout_stderr.log.
  #   * kitty is linked against Nix's own glibc and cannot safely load either
  #     vendor's driver .so on this hybrid Intel/NVIDIA host — doing so pulls
  #     the host glibc into the same process and hits a GLIBC_PRIVATE symbol
  #     clash, segfaulting regardless of Wayland/EGL vs X11/GLX.
  #
  # On NixOS both work normally, so they are installed from nixpkgs there.
  # On generic Linux install them from the host instead:
  #   kitty -> `pkg-install kitty`
  #   zoom  -> `flatpak install --user flathub us.zoom.Zoom`
  # kitty keeps its chezmoi config (chezmoi/dot_config/kitty) and stylix
  # theming via stylix.targets.kitty either way — this guards only the package.
  nixosOnlyPackages = with pkgs; [
    kitty
    zoom-us
  ];

  availablePackages =
    lib.filter (pkg: lib.meta.availableOn pkgs.stdenv.hostPlatform pkg)
    (desktopPackages ++ lib.optionals isNixos nixosOnlyPackages);
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

        # Zoom: meeting/phone links clicked in the browser. "tel" is
        # deliberately absent — kdeconnect owns it on this host.
        "x-scheme-handler/zoommtg" = [zoomDesktopId];
        "x-scheme-handler/zoomus" = [zoomDesktopId];
        "x-scheme-handler/zoomphonecall" = [zoomDesktopId];
        "x-scheme-handler/zoomphonesms" = [zoomDesktopId];
        "x-scheme-handler/zoomcontactcentercall" = [zoomDesktopId];
        "x-scheme-handler/callto" = [zoomDesktopId];
        "application/x-zoom" = [zoomDesktopId];
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
