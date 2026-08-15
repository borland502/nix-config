# Desktop-focused home-manager profile
{
  config,
  pkgs,
  lib,
  isNixos ? false,
  ...
}: let
  # Default-application associations live in TOML rather than inline Nix so the
  # same list is editable (and readable) outside the flake. Read from the repo
  # copy — flake eval is pure, so the deployed ~/.config/mimeapps/defaults.toml
  # is not reachable here; chezmoi deploys that copy from this same file.
  mimeDefaults = builtins.fromTOML (builtins.readFile ../../chezmoi/dot_config/mimeapps/defaults.toml);

  # Zoom's meeting links must open whichever Zoom actually exists on the host.
  # nixpkgs zoom-us ships "Zoom.desktop"; the Flathub build used on generic
  # Linux (see nixosOnlyPackages) ships "us.zoom.Zoom.desktop". Resolved here
  # rather than in the TOML because it is host-conditional. Declaring it
  # explicitly matters because mimeapps.list is a read-only symlink into the
  # store here, so `xdg-mime default` cannot repair a wrong association after
  # the fact.
  zoomDesktopId =
    if isNixos
    then "Zoom.desktop"
    else "us.zoom.Zoom.desktop";

  # Role name -> .desktop id. The TOML's [apps] table wins if it names a role
  # that is also defaulted here.
  desktopIds = {zoom = zoomDesktopId;} // mimeDefaults.apps;

  # [handlers] is mimetype -> role name; xdg.mimeApps wants mimetype -> [id].
  defaultApplications =
    builtins.mapAttrs
    (
      mime: role:
        if desktopIds ? ${role}
        then [desktopIds.${role}]
        else throw "mimeapps/defaults.toml: handler ${mime} names unknown app role ${role}"
    )
    mimeDefaults.handlers;

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
    #
    # inkscape was dropped: it lands as a source build here rather than a cache
    # hit, which is slow enough to dominate a switch on the weaker hosts. Add it
    # back per-host, or reach for the distro/flatpak build, if it is needed.
    gimp

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

  # plasma-manager applies the declared panel layout by feeding a JS file to
  # plasmashell over D-Bus, and the script it generates calls bare `qdbus`
  # (modules/startup.nix — not configurable). NixOS's plasma6 module adds
  # qttools to systemPackages precisely to "Expose qdbus in PATH"; a standalone
  # Home Manager host gets no such help, and distros ship the Qt6 binary under a
  # versioned name (qdbus6 on Arch/CachyOS, qdbus-qt6 on Debian/Fedora), so bare
  # `qdbus` does not exist.
  #
  # The failure is silent and destructive rather than merely inert: the script
  # deletes plasma-org.kde.plasma.desktop-appletsrc *before* the qdbus call
  # (upstream's workaround for plasma-manager#76), so every activation wiped the
  # panel and then failed to rebuild it, leaving the stock Plasma panel with
  # none of the pinned launchers declared in home.nix. It only showed up in the
  # session journal:
  #   run_all.sh[…]: …/2_desktop_script_panels.sh: line 17: qdbus: command not found
  #
  # nixpkgs' kdePackages.qttools would supply a real qdbus, but drags in ~715 MiB
  # of closure (designer, assistant, linguist) for one 40 KB binary. Shim to the
  # host's Qt6 copy instead. Kept off NixOS so it can never shadow the real one.
  qdbusShim = pkgs.writeShellScriptBin "qdbus" ''
    for candidate in qdbus6 qdbus-qt6 /usr/lib/qt6/bin/qdbus; do
      if command -v "$candidate" > /dev/null 2>&1; then
        exec "$candidate" "$@"
      fi
    done
    echo "qdbus: no Qt 6 D-Bus tool on this host (looked for qdbus6, qdbus-qt6)" >&2
    exit 127
  '';
in {
  # Desktop applications
  home.packages = availablePackages ++ lib.optional (!isNixos) qdbusShim;
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

    # Make Flatpak-installed apps visible to the desktop. On generic Linux the
    # GPU-dependent apps above come from Flathub instead of nixpkgs (see
    # nixosOnlyPackages), and their .desktop files live under
    # <install>/exports/share — not under any directory Plasma already scans.
    #
    # The distro ships /etc/profile.d/flatpak.sh to add these, but only login
    # shells source it: plasmalogin starts the Plasma session without one, so
    # the session env never learns about the Flatpak exports. The symptom is
    # subtle — the app is installed and `flatpak run` works, but it is missing
    # from Kickoff and, worse, the mimeApps associations below silently dangle:
    # xdg-open cannot resolve "us.zoom.Zoom.desktop" to anything, so Zoom
    # meeting links do nothing at all.
    #
    # Home Manager exports this from hm-session-vars.sh, which the graphical
    # session does pick up (that is how the stylix XDG_CONFIG_DIRS entry above
    # reaches Plasma). hm-session-vars.sh appends the pre-existing value via
    # ${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}, so it ONLY preserves the system dirs
    # when XDG_DATA_DIRS was already set. In the plasmalogin -> startplasma
    # chain it is empty, so /usr/local/share:/usr/share get dropped entirely —
    # and then plasmashell cannot locate the "default" plasma theme under
    # /usr/share/plasma/desktoptheme, fails to build its corona, and exits 1
    # (black screen, no panel, no cursor). List the system dirs explicitly so
    # they survive regardless of the inherited value. Prepending the Flatpak
    # dirs matches the order flatpak.sh itself uses.
    # NixOS installs these apps from nixpkgs, so it needs neither Flatpak path,
    # but the stock XDG_DATA_DIRS there already carries the system dirs.
    systemDirs.data = lib.mkIf (!isNixos) [
      "${config.xdg.dataHome}/flatpak/exports/share"
      "/var/lib/flatpak/exports/share"
      "/usr/local/share"
      "/usr/share"
    ];

    # No custom desktopEntries.vivaldi: the nixpkgs vivaldi package already
    # ships vivaldi-stable.desktop (Exec wired to the Nix binary), which is the
    # id Vivaldi self-checks against. A second vivaldi.desktop only shadows it
    # and re-triggers the "set as default" prompt.

    # Associations come from chezmoi/dot_config/mimeapps/defaults.toml
    # (deployed to ~/.config/mimeapps/defaults.toml).
    mimeApps = {
      enable = true;
      inherit defaultApplications;
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
