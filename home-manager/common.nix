# Common home-manager configuration shared between Linux and Darwin
{ config, pkgs, lib, ... }:

let
  availableOnHost = pkg: lib.meta.availableOn pkgs.stdenv.hostPlatform pkg;
  awsSamCliPatched = pkgs.aws-sam-cli.overridePythonAttrs (old: {
    # nixpkgs currently wires newer click and aws-lambda-builders versions than
    # the wheel metadata expects. Keep the package Nix-managed and skip the
    # strict runtime metadata check until upstream packaging catches up.
    doCheck = false;
    dontCheckRuntimeDeps = true;
    pythonRelaxDeps = (old.pythonRelaxDeps or [ ]) ++ [ "click" ];
  });
  commonPackages = with pkgs; [
    # Development tools
    git
    gh
    curl
    wget
    go
    go-task
    python3
    pipx
    maven
    awscli2
    awslogs
    awsSamCliPatched
    checkov
    bun

    # Container and process tooling
    docker
    docker-buildx
    docker-compose
    overmind

    # Shell integration tools
    bat
    eza
    fzf
    fd
    ripgrep
    sd
    jq
    yq-go
    zoxide
    direnv
    dasel
    tmux
    unzip

    # Productivity and content
    glow
    gum
    tealdeer
    scrcpy

    # Basic utilities
    cowsay
    file
    which
    tree
    rsync

    # System monitoring (cross-platform)
    btop
    lsof
  ];
in
{
  nixpkgs.config = {
    allowUnfree = true;
    allowUnfreePredicate = (_: true);
  };

  # Shared imports
  imports = [
    ./zsh.nix
    ./starship.nix
  ];

  # Ensure user-local binaries are found regardless of shell
  home.sessionPath = lib.mkBefore [ "$HOME/.local/bin" ];

  # Common packages shared across Linux, WSL, and macOS.
  home.packages = lib.filter availableOnHost commonPackages;

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
    base16Scheme = ./config/colors/monokai.base24.yaml;

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
      btop.enable = true;
      # Add GUI and shell-aware targets so all profiles are themed
      kitty.enable = true;
      gtk.enable = true;
      kde.enable = true;
      vscode.enable = true;
      starship.enable = true;
      # Keep qt disabled unless explicitly requested as the override is causing issues
      qt.enable = false;
    };
  };

  # VS Code: sensible default profile with Stylix theme
  programs.vscode = lib.mkIf (pkgs ? vscode) {
    enable = true;
    profiles.default = {
      userSettings = {
        # Ensure Stylix theme is selected by default
        "workbench.colorTheme" = "Stylix";
        "workbench.preferredDarkColorTheme" = "Stylix";

        # Fonts consistent with Stylix
        "editor.fontFamily" = "FiraCode Nerd Font Mono";
        "terminal.integrated.fontFamily" = "FiraCode Nerd Font Mono";
        "terminal.integrated.defaultProfile.linux" = "zsh";
        "terminal.integrated.profiles.linux" = {
          zsh = {
            path = "${pkgs.zsh}/bin/zsh";
            args = [ "-l" ];
          };
        };

        # Small quality-of-life defaults (non-Stylix)
        "editor.fontLigatures" = true;
        "editor.formatOnSave" = true;
        "files.trimTrailingWhitespace" = true;
        "files.insertFinalNewline" = true;
        "git.autofetch" = true;
      };
    };
  };

  # Common Git configuration
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "jhettenh";
        email = "jhettenh@gmail.com";
      };
      init.defaultBranch = "main";
      core.editor = "vim";
      pull.rebase = false;
    };
  };

  # Common program configurations
  programs.bat.enable = true;
  programs.dircolors = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.eza = {
    enable = true;
    enableZshIntegration = true;
    colors = "always";
    git = true;
    icons = "always";
  };

  programs.fd.enable = true;
  programs.ripgrep.enable = true;

  # Direnv for automatic environment loading
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
  };

  # Common home-manager settings
  home.stateVersion = "25.05";
  programs.home-manager.enable = true;

  programs.vim = {
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
}
