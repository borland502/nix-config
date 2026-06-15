{
  pkgs,
  lib,
  ...
}: let
  colors = import ./lib/colors.nix;
  starshipSettings = import ./lib/starship-settings.nix;
  windowsBootstrap = {
    # Set these explicitly if Windows path discovery is unreliable on a given host.
    userProfilePath = null;
    terminalPackageFamily = "Microsoft.WindowsTerminal_8wekyb3d8bbwe";
    terminalFontFace = "FiraCode Nerd Font Mono";
  };
  starshipToml = pkgs.formats.toml {};
  windowsStarshipConfig = starshipToml.generate "windows-starship.toml" starshipSettings;
  # PowerShell helper scripts from this repo's chezmoi/dot_local/bin, filtered to
  # *.ps1 only. Mirrored into the Windows user's ~/.local/bin on every switch by
  # the windowsPowerShellBootstrap activation below. Only git-tracked files are
  # included (flake source), so new scripts must be `git add`ed to ship.
  powershellBinScripts = lib.sources.sourceFilesBySuffices ../chezmoi/dot_local/bin [".ps1"];
  linuxPackages = with pkgs; [
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
    nerd-fonts.fira-code
    # PowerShell (pwsh) inside the WSL Linux guest. Gated to WSL by living in
    # this file: native Linux (home.nix) and macOS (home-darwin.nix) omit it.
    # Distinct from the windowsPowerShellBootstrap activation below, which
    # installs pwsh on the Windows host via winget.
    powershell
  ];

  availableOnHost = pkg: lib.meta.availableOn pkgs.stdenv.hostPlatform pkg;
  availableLinuxPackages = lib.filter availableOnHost linuxPackages;
  guiRuntimePackages = with pkgs; [
    libGL
    libxkbcommon
    wayland
    libx11
    libxcursor
    libxext
    libxrender
    libxfixes
    libxi
    libxinerama
    libxrandr
    libxxf86vm
  ];
  guiDevPackages = with pkgs; [
    libGL.dev
    libxkbcommon.dev
    wayland.dev
    xorgproto
    libx11.dev
    libxcursor.dev
    libxext.dev
    libxrender.dev
    libxfixes.dev
    libxi.dev
    libxinerama.dev
    libxrandr.dev
    libxxf86vm.dev
  ];
  guiPkgConfigPath =
    (lib.makeSearchPath "lib/pkgconfig" guiDevPackages)
    + ":"
    + (lib.makeSearchPath "share/pkgconfig" guiDevPackages);
  guiIncludePath = lib.makeSearchPath "include" guiDevPackages;
  guiLibraryPath = lib.makeLibraryPath guiRuntimePackages;
  codeEditorUserSettings = import ./lib/code-editor-user-settings.nix {
    inherit pkgs;
    homeDirectory = config.home.homeDirectory;
  };
in {
  _module.args.isWsl = true;

  imports = [
    ./common.nix
    ./profiles/development-linux.nix
  ];

  home = {
    username = lib.mkDefault "jhettenh";
    homeDirectory = lib.mkDefault "/home/jhettenh";

    packages = availableLinuxPackages;

    sessionVariables = {
      # Keep CGO GUI builds working in a regular WSL shell without a separate nix develop step.
      PKG_CONFIG_PATH = guiPkgConfigPath;
      CPATH = guiIncludePath;
      LIBRARY_PATH = guiLibraryPath;
      LD_LIBRARY_PATH = guiLibraryPath;
      GDK_BACKEND = "wayland,x11";
      QT_QPA_PLATFORM = "wayland;xcb";
      SDL_VIDEODRIVER = "wayland,x11";
      CLUTTER_BACKEND = "wayland";
      MOZ_ENABLE_WAYLAND = "1";
      NIXOS_OZONE_WL = "1";
    };

    activation.dconfSettings = lib.mkForce (
      lib.hm.dag.entryAfter ["checkLinkTargets"] ''
        echo "Skipping dconfSettings in WSL (no dconf service available)."
      ''
    );

    # Deploy this repo's PowerShell helper scripts and the Windows starship
    # config into the Windows user's home on every switch — WITHOUT Windows
    # interop on the hot path. The Windows home comes from
    # windowsBootstrap.userProfilePath if set, else a cached value, else is
    # resolved once via a single bounded interop call and cached; after the
    # first resolution every switch is pure filesystem. wslpath is a local WSL
    # tool (/init), not Windows interop. Execution policy and broader Windows
    # tooling live in `task wsl-bootstrap-windows`, not here.
    activation.windowsHelperScripts = lib.hm.dag.entryAfter ["writeBoundary"] ''
      cat_exe="${pkgs.coreutils}/bin/cat"
      dirname_exe="${pkgs.coreutils}/bin/dirname"
      mkdir_exe="${pkgs.coreutils}/bin/mkdir"
      install_exe="${pkgs.coreutils}/bin/install"
      tr_exe="${pkgs.coreutils}/bin/tr"
      timeout_exe="${pkgs.coreutils}/bin/timeout"
      windows_powershell_exe="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
      cache_file="$HOME/.local/state/nix-config/windows-home"

      # wslpath is distro-dependent (NixOS-WSL: /bin/wslpath -> /init;
      # Debian/Ubuntu: /usr/bin/wslpath). It is a local tool, not interop.
      wslpath_exe=""
      for _wslpath_cand in /usr/bin/wslpath /bin/wslpath /sbin/wslpath; do
        if [ -x "$_wslpath_cand" ]; then wslpath_exe="$_wslpath_cand"; break; fi
      done
      if [ -z "$wslpath_exe" ]; then
        wslpath_exe="$(command -v wslpath 2>/dev/null || true)"
      fi

      windows_home_unix=""
      # 1) Explicit config override — no interop.
      ${lib.optionalString (windowsBootstrap.userProfilePath != null) ''
        if [ -n "$wslpath_exe" ]; then
          windows_home_unix="$("$wslpath_exe" -u '${windowsBootstrap.userProfilePath}' 2>/dev/null || true)"
        fi
      ''}
      # 2) Cached value from a previous resolution — no interop.
      if { [ -z "$windows_home_unix" ] || [ ! -d "$windows_home_unix" ]; } && [ -r "$cache_file" ]; then
        windows_home_unix="$("$cat_exe" "$cache_file" 2>/dev/null || true)"
      fi
      # 3) One-time bounded interop resolution, then cache (never repeats once
      #    cached). This is the only interop this activation can do, and only on
      #    a cold cache.
      if { [ -z "$windows_home_unix" ] || [ ! -d "$windows_home_unix" ]; } && [ -x "$windows_powershell_exe" ] && [ -n "$wslpath_exe" ]; then
        _win_path="$($timeout_exe -k 5 15 "$windows_powershell_exe" -NoProfile -Command "[Environment]::GetFolderPath('UserProfile')" 2>/dev/null | $tr_exe -d '\r' || true)"
        if [ -n "$_win_path" ]; then
          windows_home_unix="$("$wslpath_exe" -u "$_win_path" 2>/dev/null || true)"
          if [ -n "$windows_home_unix" ] && [ -d "$windows_home_unix" ]; then
            $mkdir_exe -p "$("$dirname_exe" "$cache_file")" || true
            printf '%s\n' "$windows_home_unix" > "$cache_file" || true
          fi
        fi
      fi

      if [ -n "$windows_home_unix" ] && [ -d "$windows_home_unix" ]; then
        _win_localbin="$windows_home_unix/.local/bin"
        _win_config="$windows_home_unix/.config"
        $mkdir_exe -p "$_win_localbin" "$_win_config" || true
        $install_exe -m 0644 ${windowsStarshipConfig} "$_win_config/starship.toml" || true
        for ps_script in ${powershellBinScripts}/*.ps1; do
          [ -e "$ps_script" ] || continue
          # Drop chezmoi's executable_ source prefix; deploy 0755 (cosmetic on
          # NTFS — .ps1 execution is gated by the PowerShell execution policy,
          # which `task wsl-bootstrap-windows` sets to RemoteSigned).
          ps_name="''${ps_script##*/}"
          ps_name="''${ps_name#executable_}"
          $install_exe -m 0755 "$ps_script" "$_win_localbin/$ps_name" || true
        done
      else
        echo "Skipping Windows helper-script deploy: Windows home not resolved. Run 'task wsl-bootstrap-windows' once, or set windowsBootstrap.userProfilePath."
      fi
    '';

    file.".vscode-server/data/User/settings.json".text = builtins.toJSON codeEditorUserSettings;

    file.".vscode-server/data/Machine/settings.json".text = builtins.toJSON {
      "terminal.integrated.automationProfile.linux" = {
        path = "${pkgs.zsh}/bin/zsh";
        args = ["-l"];
      };
    };
  };

  stylix.targets = {
    bat.enable = lib.mkForce true;
    btop.enable = lib.mkForce true;
    fzf.enable = lib.mkForce true;
    kitty.enable = true;
    starship.enable = lib.mkForce true;
    vim.enable = lib.mkForce true;
    vscode.enable = true;
    gtk.enable = lib.mkForce false;
    kde.enable = lib.mkForce false;
  };

  programs.starship.settings = {
    format = lib.mkForce "$os$username$hostname$directory$git_branch$git_status$nix_shell$nodejs$python$rust$golang$docker_context$aws$cmd_duration$line_break$time$character";

    username.show_always = lib.mkForce true;

    hostname = {
      ssh_only = lib.mkForce false;
      format = lib.mkForce "[@$hostname]($style) ";
      style = lib.mkForce "${colors.base09} bold";
    };

    directory.truncation_length = lib.mkForce 5;
  };

  programs.zsh.envExtra = lib.mkAfter ''
    export PKG_CONFIG_PATH="${guiPkgConfigPath}''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    export CPATH="${guiIncludePath}''${CPATH:+:$CPATH}"
    export LIBRARY_PATH="${guiLibraryPath}''${LIBRARY_PATH:+:$LIBRARY_PATH}"
    export LD_LIBRARY_PATH="${guiLibraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  '';

  fonts.fontconfig.defaultFonts = {
    sansSerif = lib.mkAfter ["DejaVu Sans"];
    serif = lib.mkAfter ["DejaVu Serif"];
  };
}
