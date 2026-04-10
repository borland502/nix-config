# Common home-manager configuration shared between Linux and Darwin
{
  pkgs,
  lib,
  isWsl ? false,
  ...
}: let
  availableOnHost = pkg: lib.meta.availableOn pkgs.stdenv.hostPlatform pkg;
  codeEditorUserSettings = import ./lib/code-editor-user-settings.nix {inherit pkgs;};
  awsSamCliPatched = pkgs.aws-sam-cli.overridePythonAttrs (old: {
    # nixpkgs currently wires newer click and aws-lambda-builders versions than
    # the wheel metadata expects. Keep the package Nix-managed and skip the
    # strict runtime metadata check until upstream packaging catches up.
    doCheck = false;
    dontCheckRuntimeDeps = true;
    pythonRelaxDeps = (old.pythonRelaxDeps or []) ++ ["click"];
  });
  direnvPatched =
    if pkgs.stdenv.isDarwin
    then
      pkgs.direnv.overrideAttrs (old: {
        env = (old.env or {}) // {CGO_ENABLED = "1";};
      })
    else pkgs.direnv;
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
    direnvPatched
    dasel
    tmux
    unzip
    p7zip
    age
    alejandra
    ncdu
    statix
    deadnix
    nixd
    unison

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
  copilotDefaultsFile = ./config/copilot/copilot-defaults.instructions.md;
in {
  nixpkgs.config = {
    allowUnfree = true;
    allowUnfreePredicate = _: true;
  };

  # Shared imports
  imports = [
    ./zsh.nix
    ./starship.nix
  ];

  home = {
    # Ensure user-local binaries are found regardless of shell
    sessionPath = lib.mkBefore ["$HOME/.local/bin"];

    # Common packages shared across Linux, WSL, and macOS.
    packages = lib.filter availableOnHost commonPackages;

    # Common home-manager settings
    stateVersion = "25.05";

    # Make Copilot defaults visible to desktop, remote, and shared IDE sessions.
    file =
      {
        ".config/Code/User/prompts/copilot-defaults.instructions.md".source = copilotDefaultsFile;
        ".config/Code - Insiders/User/prompts/copilot-defaults.instructions.md".source = copilotDefaultsFile;
        ".vscode-server/data/User/prompts/copilot-defaults.instructions.md".source = copilotDefaultsFile;
        ".vscode-server-insiders/data/User/prompts/copilot-defaults.instructions.md".source = copilotDefaultsFile;
        ".config/github-copilot/copilot-defaults.instructions.md".source = copilotDefaultsFile;
        ".config/github-copilot/intellij/global-copilot-instructions.md".source = copilotDefaultsFile;
      }
      // lib.optionalAttrs (!isWsl && pkgs.stdenv.isLinux) {
        ".config/Code - Insiders/User/settings.json".text = builtins.toJSON codeEditorUserSettings;
      };
  };

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

  programs = {
    # VS Code: sensible default profile with Stylix theme
    vscode = lib.mkIf (!isWsl && pkgs ? vscode) {
      enable = true;
      profiles.default = {
        extensions = lib.mkAfter [pkgs.vscode-extensions.jnoortheen.nix-ide];
        userSettings = codeEditorUserSettings;
      };
    };

    # Common Git configuration
    git = {
      enable = true;
      settings = {
        user = {
          name = "jhettenh";
          email = "jhettenh@gmail.com";
        };
        init.defaultBranch = "main";
        core.editor = "vim";
        pull.rebase = false;
        push.autoSetupRemote = true;
      };
    };

    # Common program configurations
    bat.enable = true;
    dircolors = {
      enable = true;
      enableZshIntegration = true;
    };

    eza = {
      enable = true;
      enableZshIntegration = true;
      colors = "always";
      git = true;
      icons = "always";
    };

    fd.enable = true;
    ripgrep.enable = true;

    # Direnv for automatic environment loading
    direnv = {
      enable = true;
      enableZshIntegration = true;
      package = direnvPatched;
    };

    home-manager.enable = true;

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
