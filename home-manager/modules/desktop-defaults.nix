{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (config.nixConfig.host) isWsl;
  codeEditorUserSettings = import ../lib/code-editor-user-settings.nix {
    inherit pkgs;
  };
in {
  # Common font configuration
  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      monospace = [
        "FiraCode Nerd Font Mono"
        "FiraCode Nerd Font"
        "Fira Code"
        "JetBrainsMono Nerd Font"
        "Source Code Pro"
      ];
      sansSerif = [
        "FiraCode Nerd Font Propo"
        "Inter"
        "Helvetica"
        "Arial"
        "DejaVu Sans"
      ];
      serif = [
        "Liberation Serif"
        "Times New Roman"
        "Times"
        "DejaVu Serif"
      ];
    };
  };

  # Common Stylix configuration
  stylix = {
    enable = true;
    base16Scheme = let
      raw = fromTOML (builtins.readFile ../../chezmoi/dot_config/colors/monokai.toml);
    in {
      inherit (raw) system name author variant palette;
    };

    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.fira-code;
        name = "FiraCode Nerd Font Mono";
      };
      sansSerif = {
        package = pkgs.inter;
        name = "Inter";
      };
      serif = {
        package = pkgs.liberation_ttf;
        name = "Liberation Serif";
      };
    };

    # Common theming targets (applies to Linux and macOS)
    targets = {
      bat.enable = true;
      fzf.enable = true;
      vim.enable = true;
      neovim.enable = true;
      tmux.enable = true;
      btop.enable = true;
      lazygit.enable = true;
      # Add GUI and shell-aware targets so all profiles are themed
      kitty.enable = true;
      gtk.enable = true;
      kde.enable = true;
      vscode.enable = true;
      starship.enable = true;
      # Keep qt disabled. The target exports QT_QPA_PLATFORMTHEME=qt5ct and
      # QT_STYLE_OVERRIDE=kvantum session-wide, which displaces Plasma's own
      # platform theme — and the kde target above already themes Qt/KDE apps
      # natively by injecting stylix-kde-config into XDG_CONFIG_DIRS. Enabling
      # both just makes them fight over the same apps for no gain; the only
      # thing it would buy is theming Qt apps run outside a Plasma session.
      #
      # Not to be confused with home-manager#6565 ("any qt dependency/setting
      # makes non-nixOS host systemd unusable"), which is why stylix gates this
      # target behind `nixosConfig != null`. That issue is still open upstream,
      # but was retested on CachyOS (standalone HM) 2026-08-14 and no longer
      # reproduces: enabling qt leaves the systemd closure byte-identical (7
      # paths before and after) and puts no systemd binaries on PATH — it adds
      # only qt5ct, qt6ct, kvantummanager, kvantumpreview.
      #
      # If this is ever wanted, `stylix.targets.qt.platform = "kde"` yields
      # platformTheme=kde / style=breeze / kvantum off, which is Plasma-
      # consistent, at the cost of an "unsupported platform" warning.
      qt.enable = false;
      # Stylix's gnome target auto-enables on every Linux build and fetches the
      # gnome-shell source tarball from gitlab.gnome.org at eval time to derive
      # gnome-shell.css. That endpoint is unreliable (HTTP/2 stream truncation,
      # 503s) and has been failing `nix flake check` in CI on every run. No host
      # here runs GNOME Shell, so disable the target outright. (No-op on macOS,
      # where the target does not auto-enable.)
      gnome.enable = false;
    };
  };

  programs = {
    # VS Code: sensible default profile with Stylix theme
    vscode = lib.mkIf (!isWsl && pkgs ? vscode) {
      enable = true;
      profiles.default = {
        extensions = lib.mkAfter [pkgs.vscode-extensions.jnoortheen.nix-ide];
        userSettings = codeEditorUserSettings;
      };
    };

    vim = {
      enable = true;
      defaultEditor = true;
      plugins = with pkgs.vimPlugins; [
        vim-airline
        vim-airline-themes
        nerdtree
        vim-fugitive
        vim-surround
        vim-commentary
        coc-nvim
        monokai-pro-nvim
      ];
    };
  };
}
