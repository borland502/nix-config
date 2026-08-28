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

    # Game streaming. moonlight-qt decodes in hardware, so it needs working
    # GLX/EGL. If it aborts on a non-NixOS host the way zoom-us does, move it
    # to nixosOnlyPackages below and install the Flathub build there instead
    # (`flatpak install --user flathub com.moonlight_stream.Moonlight`).
    moonlight-qt

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

    # Remote desktop client. This is the other end of the KRdp server in
    # modules/desktop/krdp.nix: those hosts keep 3389 closed and are reached by
    # forwarding it over the ssh-only front door, e.g.
    #   ssh -N -L 3389:localhost:3389 tifa
    # and then pointing remmina at localhost:3389.
    #
    # Plain GTK/FreeRDP with no GL requirement, so unlike kitty and zoom-us it
    # does not need nixosOnlyPackages — it runs from nixpkgs on the generic
    # Linux hosts too.
    remmina
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
  #   kitty -> installed automatically by
  #            chezmoi/run_onchange_provision-linux-host.sh.tmpl (it has to
  #            exist on every host: home-manager wires a KDE global shortcut
  #            and the default-terminal association straight to
  #            kitty.desktop, which comes up blank if the package is absent)
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

  # Nix-built browsers hand their own LD_LIBRARY_PATH to every child process,
  # and that is fatal for a child that is a *host* binary.
  #
  # nixpkgs wraps vivaldi with `--prefix LD_LIBRARY_PATH` pointing at Nix's
  # glibc and friends. Chromium then spawns distro helpers by absolute path,
  # which inherit that variable and get Nix's libc loaded by the host
  # ld-linux. The two disagree over GLIBC_PRIVATE, so the process dies inside
  # the dynamic loader — before main(), with a backtrace that is pure
  # ld.so/__getrandom_early_init and names neither culprit. Verified on this
  # host: the same command is rc=0 normally and rc=139 with the variable set.
  #
  # It is the same glibc-mixing hazard already described for kitty above,
  # reached from the other direction: there a Nix binary loads host driver
  # .so files, here a host binary loads Nix libc.
  #
  # Observed victims, both spawned by Vivaldi:
  #   xdg-settings                     — the default-browser check, so Vivaldi
  #                                      re-prompts every launch
  #   plasma-browser-integration-host  — KDE's native-messaging bridge, so the
  #                                      Plasma browser integration is dead
  # Both also spammed systemd-coredump on a loop.
  #
  # The shim re-execs the real host binary with the variable removed. Kept off
  # NixOS, where nothing under /usr/bin exists to defer to and the whole
  # mismatch cannot arise.
  hostHelperShim = name:
    pkgs.writeShellScriptBin name ''
      real=/usr/bin/${name}
      if [ ! -x "$real" ]; then
        echo "${name}: no host binary at $real" >&2
        exit 127
      fi
      exec ${pkgs.coreutils}/bin/env -u LD_LIBRARY_PATH "$real" "$@"
    '';

  xdgSettingsShim = hostHelperShim "xdg-settings";
  plasmaBrowserIntegrationShim = hostHelperShim "plasma-browser-integration-host";
in {
  # Desktop applications
  home.packages =
    availablePackages
    ++ lib.optionals (!isNixos) [
      qdbusShim
      xdgSettingsShim
      plasmaBrowserIntegrationShim
    ];
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

    # Point KDE's native-messaging bridge at the LD_LIBRARY_PATH-scrubbing shim
    # (see hostHelperShim above for why the unwrapped binary segfaults).
    #
    # A PATH shim is not enough on its own here: unlike xdg-settings, this
    # helper is not looked up on PATH at all. The browser reads its absolute
    # path out of a manifest — the distro's copy in
    # /etc/chromium/native-messaging-hosts names /usr/bin directly. A
    # user-level manifest takes precedence over the system one, so this
    # redirects it without touching /etc.
    #
    # allowed_origins is copied verbatim from the distro manifest: those are
    # the extension IDs of the Plasma Integration add-on, and the browser
    # refuses the connection if the requesting extension is not listed.
    configFile."vivaldi/NativeMessagingHosts/org.kde.plasma.browser_integration.json" = lib.mkIf (!isNixos) {
      text = builtins.toJSON {
        name = "org.kde.plasma.browser_integration";
        description = "Native connector for KDE Plasma";
        path = "${plasmaBrowserIntegrationShim}/bin/plasma-browser-integration-host";
        type = "stdio";
        allowed_origins = [
          "chrome-extension://cimiefiiaegbelhefglklhhakcgmhkai/"
          "chrome-extension://dnnckbejblnejeabhcmhklcaljjpdjeh/"
        ];
      };
    };

    # KeePassXC's browser bridge, for the same reason as the Plasma one above:
    # the browser reads an absolute path out of a manifest, so the proxy has to
    # be named explicitly.
    #
    # KeePassXC can write this file itself, from Settings -> Browser
    # Integration, but only for the browsers it knows and only into the paths
    # the running build was compiled with. Doing it here instead means the
    # manifest points at THIS nix-profile proxy rather than whatever
    # /usr/bin/keepassxc-proxy a distro package might drop in later, and that it
    # survives a profile wipe.
    #
    # Two halves are required and only one of them lives here: without
    # `[Browser] Enabled=true` in keepassxc.ini, KeePassXC never opens the
    # socket the proxy connects to, and the extension sits on "Checking
    # status..." forever with no error. That half is asserted by
    # chezmoi/dot_config/keepassxc/modify_keepassxc.ini — change both together.
    #
    # allowed_origins is the KeePassXC-Browser extension ID; the browser refuses
    # the connection if the requesting extension is not listed.
    configFile."vivaldi/NativeMessagingHosts/org.keepassxc.keepassxc_browser.json" = lib.mkIf (!isNixos) {
      text = builtins.toJSON {
        name = "org.keepassxc.keepassxc_browser";
        description = "KeePassXC integration with native messaging support";
        path = "${pkgs.keepassxc}/bin/keepassxc-proxy";
        type = "stdio";
        allowed_origins = [
          "chrome-extension://oboonakemofpalcgghocfoadofidjkkk/"
        ];
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
