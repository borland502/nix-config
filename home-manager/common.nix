# Common home-manager configuration shared between Linux and Darwin
{ config, pkgs, lib, ... }:

let
  copilotInstructionsFileName = "copilot-defaults.instructions.md";
  copilotInstructionsText = ''
    ---
    description: "Use for every task. Persistent defaults for terminal commands, shell usage, and command logging. Prefer non-interactive commands and log command plus output to ~/.cache/copilot."
    name: "Persistent Terminal Logging Defaults"
    applyTo: "**"
    ---
    # Persistent Terminal Defaults

    - Prefer non-interactive commands over interactive shells unless the task explicitly requires an interactive program.
    - Minimize use of interactive terminal flows that can mangle command output in the IDE.
    - When running terminal commands, also write the exact command and the resulting output to files under ~/.cache/copilot.
    - Ensure ~/.cache/copilot exists before attempting to write logs there.
    - Use append-safe logging or timestamped files so earlier command logs are not lost unless replacement is explicitly intended.
  '';
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

  home.file = lib.mkMerge [
    (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      "Library/Application Support/Code/User/prompts/${copilotInstructionsFileName}".text = copilotInstructionsText;
    })
    (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      ".config/Code/User/prompts/${copilotInstructionsFileName}".text = copilotInstructionsText;
      ".vscode-server/data/User/prompts/${copilotInstructionsFileName}".text = copilotInstructionsText;
    })
  ];

  home.activation.ensureCopilotCacheDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.cache/copilot"
  '';

  # Common packages (platform-agnostic)
  home.packages = with pkgs; [
    # Development tools
    git
    gh
    curl
    wget
    go-task

    # Shell integration tools
    bat        # Better cat with syntax highlighting
    eza        # Modern ls replacement
    fzf        # Fuzzy finder
    fd         # Better find
    ripgrep    # Fast text search
    sd         # Better sed
    jq         # JSON processor
    yq         # YAML processor
    zoxide     # Smart cd replacement

    # Productivity and content
    glow
    gum
    tealdeer

    # Basic utilities
    cowsay
    file
    which
    tree
    # ncdu # Disabling to avoid LLVM/Zig build issues
    rsync
    direnv
    unzip

    # System monitoring (cross-platform)
    btop
    lsof
  ];

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
      # Temporary disabled due to LLVM/Zig build issues causing build failures on macOS
      firefox.enable = lib.mkForce false;
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
        "terminal.integrated.shellIntegration.enabled" = true;

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
