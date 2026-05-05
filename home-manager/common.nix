# Common home-manager configuration shared between Linux and Darwin
{
  config,
  pkgs,
  lib,
  isWsl ? false,
  ...
}: let
  availableOnHost = pkg: lib.meta.availableOn pkgs.stdenv.hostPlatform pkg;
  inherit (config.home) homeDirectory;
  xdgBinHome = "${homeDirectory}/.local/bin";
  xdgCacheHome = "${homeDirectory}/.cache";
  xdgConfigHome = "${homeDirectory}/.config";
  xdgDataHome = "${homeDirectory}/.local/share";
  xdgLibHome = "${homeDirectory}/.local/lib";
  xdgStateHome = "${homeDirectory}/.local/state";
  xdgDirectories = [
    xdgBinHome
    xdgCacheHome
    xdgConfigHome
    xdgDataHome
    xdgLibHome
    xdgStateHome
  ];
  codeEditorUserSettings = import ./lib/code-editor-user-settings.nix {inherit pkgs;};
  vividTheme = import ./lib/vivid-theme.nix {inherit lib pkgs;};
  # Bake LS_COLORS at build time from the repo's monokai palette so ls/eza/tree
  # share the rest of the theme. Read at shell init via $(cat ...) — kernel
  # caches the /nix/store file so the cost is effectively zero.
  lsColors = pkgs.runCommand "ls-colors" {} ''
    ${pkgs.vivid}/bin/vivid generate ${vividTheme} > $out
  '';
  awsSamCliPatched = pkgs.aws-sam-cli.overridePythonAttrs (old: {
    # nixpkgs currently wires newer click and aws-lambda-builders versions than
    # the wheel metadata expects. Keep the package Nix-managed and skip the
    # strict runtime metadata check until upstream packaging catches up.
    doCheck = false;
    dontCheckRuntimeDeps = true;
    pythonRelaxDeps = (old.pythonRelaxDeps or []) ++ ["click"];
  });
  python3Patched =
    pkgs.python3
    // {
      override = args:
        pkgs.python3.override (args
          // {
            packageOverrides =
              lib.composeExtensions
              (args.packageOverrides or (_: _: {}))
              (_: prev: {
                imageio-ffmpeg = prev.imageio-ffmpeg.overridePythonAttrs (_: {
                  doCheck = false;
                });
                imageio = prev.imageio.overridePythonAttrs (_: {
                  doCheck = false;
                });
              });
          });
    };
  checkovPatched = pkgs.callPackage (pkgs.path + "/pkgs/by-name/ch/checkov/package.nix") {
    python3 = python3Patched;
  };
  direnvPatched =
    if pkgs.stdenv.isDarwin
    then
      pkgs.direnv.overrideAttrs (old: {
        env = (old.env or {}) // {CGO_ENABLED = "1";};
        doCheck = false;
      })
    else pkgs.direnv;
  commonPackages = with pkgs; [
    # Development tools
    git
    gh
    curl
    wget
    gcc
    go
    gopls
    govulncheck
    delve
    go-task
    pkg-config
    python3
    pipx
    maven
    awscli2
    awslogs
    awsSamCliPatched
    checkovPatched
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

    # AI development tools
    claude-code
    github-copilot-cli

    # Secret management
    sops

    # Imperative dotfiles management
    chezmoi

    # Basic utilities
    file
    which
    tree
    rsync

    # System monitoring (cross-platform)
    btop
    lsof
  ];
  agentInstructions = import ./lib/agent-instructions.nix {inherit pkgs;};
  copilotDefaultsFile = agentInstructions.copilot;
  claudeDefaultsFile = agentInstructions.claude;
  logBashScript = pkgs.writeText "claude-log-bash.sh" ''
    #!/bin/bash
    input=$(cat)
    cmd=$(printf '%s' "$input" | ${pkgs.jq}/bin/jq -r '.tool_input.command // ""')
    sid=$(printf '%s' "$input" | ${pkgs.jq}/bin/jq -r '.session_id // "nosid"')
    resp=$(printf '%s' "$input" | ${pkgs.jq}/bin/jq -r '
      if .tool_response == null then ""
      elif (.tool_response | type) == "string" then .tool_response
      else .tool_response | tostring
      end')
    logfile="$HOME/.cache/claude/session_''${sid}.log"
    mkdir -p "$(dirname "$logfile")"
    {
      printf '\n## [%s]\n' "$(date '+%Y-%m-%d %H:%M:%S')"
      printf 'CMD: %s\n' "$cmd"
      printf 'OUTPUT:\n%s\n' "$resp"
      printf -- '---\n'
    } >> "$logfile"
  '';
in {
  nixpkgs.config = {
    allowUnfree = true;
    allowUnfreePredicate = _: true;
  };

  # Shared imports
  imports = [
    ./zsh.nix
    ./starship.nix
    ./modules/sops.nix
  ];

  xdg = {
    enable = true;
    cacheHome = xdgCacheHome;
    configHome = xdgConfigHome;
    dataHome = xdgDataHome;
    stateHome = xdgStateHome;

    # Canonical XDG location for Claude Code global user instructions.
    # CLAUDE_CONFIG_DIR (exported in zsh.nix as $XDG_CONFIG_HOME/claude) drives
    # state files like .claude.json, but does NOT drive memory-file resolution
    # — see also home.file.".claude/CLAUDE.md" below.
    configFile."claude/CLAUDE.md".source = claudeDefaultsFile;
    configFile."claude/log-bash.sh".source = logBashScript;
  };

  home = {
    # Ensure user-local binaries are found regardless of shell
    sessionPath = lib.mkBefore [xdgBinHome];

    sessionVariables = {
      GOBIN = xdgBinHome;
      XDG_BIN_HOME = xdgBinHome;
      XDG_CACHE_HOME = xdgCacheHome;
      XDG_CONFIG_HOME = xdgConfigHome;
      XDG_DATA_HOME = xdgDataHome;
      XDG_LIB_HOME = xdgLibHome;
      XDG_STATE_HOME = xdgStateHome;
      LS_COLORS = "$(${pkgs.coreutils}/bin/cat ${lsColors})";
    };

    activation = {
      ensureClaudeHook = lib.hm.dag.entryAfter ["writeBoundary"] ''
        _settings="${xdgConfigHome}/claude/settings.json"
        if [ ! -f "$_settings" ]; then
          ${pkgs.coreutils}/bin/printf '%s\n' '{}' > "$_settings"
        fi
        if ! ${pkgs.jq}/bin/jq -e '.hooks.PostToolUse[]? | select(.matcher == "Bash")' "$_settings" > /dev/null 2>&1; then
          _tmp=$(${pkgs.coreutils}/bin/mktemp)
          ${pkgs.jq}/bin/jq \
            '.hooks.PostToolUse |= (. // []) + [{"matcher":"Bash","hooks":[{"type":"command","command":"bash \"''${CLAUDE_CONFIG_DIR:-$HOME/.config/claude}/log-bash.sh\"","async":true}]}]' \
            "$_settings" > "$_tmp" && ${pkgs.coreutils}/bin/mv "$_tmp" "$_settings"
        fi
      '';

      ensureXdgDirectories = lib.hm.dag.entryAfter ["writeBoundary"] ''
        ${pkgs.coreutils}/bin/mkdir -p ${lib.concatMapStringsSep " " lib.escapeShellArg xdgDirectories}
      '';

      # Enforce ~/.cache/claude -> ~/.cache/copilot so both agents share one log dir.
      ensureCacheClaudeSymlink = lib.hm.dag.entryAfter ["ensureXdgDirectories"] ''
        ${pkgs.coreutils}/bin/mkdir -p "${xdgCacheHome}/copilot"
        if [ ! -L "${xdgCacheHome}/claude" ] || [ "$(${pkgs.coreutils}/bin/readlink "${xdgCacheHome}/claude")" != "${xdgCacheHome}/copilot" ]; then
          ${pkgs.coreutils}/bin/rm -rf "${xdgCacheHome}/claude"
          ${pkgs.coreutils}/bin/ln -s "${xdgCacheHome}/copilot" "${xdgCacheHome}/claude"
        fi
      '';

      # Configure chezmoi to use the nix-config repo as its source of truth.
      # The repo path is recorded to ~/.local/state/chezmoi/nix-config-dir by
      # the _record-nix-config-dir task whenever any switch task runs, so this
      # wiring survives the repo being renamed or moved.
      configureChezmoi = lib.hm.dag.entryAfter ["ensureXdgDirectories"] ''
        _cm_dir_file="${xdgStateHome}/chezmoi/nix-config-dir"
        _cm_age_key="${homeDirectory}/.config/sops/age/keys.txt"
        if [ -f "$_cm_dir_file" ]; then
          _cm_nix_dir=$(${pkgs.coreutils}/bin/cat "$_cm_dir_file")
          _cm_source="$_cm_nix_dir/chezmoi"
          if [ -d "$_cm_source" ]; then
            ${pkgs.coreutils}/bin/mkdir -p "${xdgConfigHome}/chezmoi"
            {
              ${pkgs.coreutils}/bin/printf 'sourceDir = "%s"\n' "$_cm_source"
              if [ -f "$_cm_age_key" ]; then
                ${pkgs.coreutils}/bin/printf 'encryption = "age"\n'
                ${pkgs.coreutils}/bin/printf '\n[age]\n'
                ${pkgs.coreutils}/bin/printf '  identity = "%s"\n' "$_cm_age_key"
              fi
            } > "${xdgConfigHome}/chezmoi/chezmoi.toml"
          fi
        fi
      '';
    };

    # Common packages shared across Linux, WSL, and macOS.
    packages = lib.filter availableOnHost commonPackages;

    # Common home-manager settings
    stateVersion = "25.05";

    # Make Copilot defaults visible to desktop, remote, and shared IDE sessions.
    file = {
      ".config/Code/User/prompts/copilot-defaults.instructions.md".source = copilotDefaultsFile;
      ".vscode-server/data/User/prompts/copilot-defaults.instructions.md".source = copilotDefaultsFile;
      ".config/github-copilot/copilot-defaults.instructions.md".source = copilotDefaultsFile;
      ".config/github-copilot/intellij/global-copilot-instructions.md".source = copilotDefaultsFile;

      # Claude Code's memory-file loader hardcodes ~/.claude/CLAUDE.md and does
      # not honor CLAUDE_CONFIG_DIR — see https://code.claude.com/docs/en/memory.md.
      # PR #20 moved this file to the XDG location alone, which silently broke
      # auto-loading. Until Anthropic teaches the loader to follow
      # CLAUDE_CONFIG_DIR (or another XDG-aware mechanism), we deploy the same
      # source to both paths so XDG remains canonical and the legacy path acts
      # as a forwarding pointer the loader can find. Revisit and remove this
      # entry once the upstream fix lands.
      ".claude/CLAUDE.md".source = claudeDefaultsFile;
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
    base16Scheme = let
      raw = builtins.fromTOML (builtins.readFile ../chezmoi/dot_config/colors/monokai.toml);
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
      };
    };

    # Common program configurations
    bat.enable = true;
    tmux.enable = true;
    neovim.enable = true;

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
