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
    opsAgent
    cacheScan

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
  # Home-manager-managed agent-instruction destinations (paths relative to $HOME).
  # Single list keeps the home.file refactor and the orphan-backup activation
  # hook below pointing at the same set of files.
  copilotInstructionPaths = [
    ".config/Code/User/prompts/copilot-defaults.instructions.md"
    ".vscode-server/data/User/prompts/copilot-defaults.instructions.md"
    ".config/github-copilot/copilot-defaults.instructions.md"
    ".config/github-copilot/intellij/global-copilot-instructions.md"
  ];
  agentInstructionDestPaths =
    [
      "${xdgConfigHome}/claude/CLAUDE.md"
      "${homeDirectory}/.claude/CLAUDE.md"
    ]
    ++ map (p: "${homeDirectory}/${p}") copilotInstructionPaths;
  opsAgentPython = pkgs.python3.withPackages (ps: [ps.anthropic]);
  opsAgent = pkgs.writeShellScriptBin "ops-agent" ''
    exec ${opsAgentPython}/bin/python ${./local/bin/ops-agent.py} "$@"
  '';
  cacheScan = pkgs.writeShellScriptBin "cache-scan" ''
    exec ${pkgs.bash}/bin/bash ${./local/bin/cache-scan.sh} "$@"
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

    configFile = {
      # Canonical XDG location for Claude Code global user instructions.
      # CLAUDE_CONFIG_DIR (exported in zsh.nix as $XDG_CONFIG_HOME/claude) drives
      # state files like .claude.json, but does NOT drive memory-file resolution
      # — see also home.file.".claude/CLAUDE.md" below.
      # `force = true` because home-manager canonically owns this file; any
      # pre-existing real file at the destination is moved aside by the
      # backupAgentInstructions activation hook below before this is written.
      "claude/CLAUDE.md" = {
        source = claudeDefaultsFile;
        force = true;
      };
      "claude/log-bash.sh".source = ./local/bin/log-bash.sh;

      # Single source of truth for custom agent/skill definitions is the
      # top-level ai-tools/ directory (modeled on the obra/superpowers layout).
      # Deploy those definitions into both Claude's and Copilot's XDG config
      # paths so the same plugin content is available to both CLIs.
      # COPILOT_CONFIG_DIR (exported in zsh.nix as $XDG_CONFIG_HOME/copilot)
      # is the parallel of CLAUDE_CONFIG_DIR for Copilot-side tooling.
      "claude/agents" = {
        source = ../ai-tools/agents;
        recursive = true;
      };
      "claude/skills" = {
        source = ../ai-tools/skills;
        recursive = true;
      };
      "copilot/agents" = {
        source = ../ai-tools/agents;
        recursive = true;
      };
      "copilot/skills" = {
        source = ../ai-tools/skills;
        recursive = true;
      };
    };
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
      # Move any pre-existing real file at an HM-owned agent-instruction path
      # aside before checkLinkTargets runs. Eliminates "Existing file would be
      # clobbered" failures when bootstrapping a host where another tool (e.g.
      # an older chezmoi config, manual edit) placed the file first. Backup
      # filenames are timestamped so repeated runs don't overwrite earlier
      # backups. Symlinks are left alone — they're already HM-owned.
      backupAgentInstructions = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
        for f in ${lib.concatMapStringsSep " " lib.escapeShellArg agentInstructionDestPaths}; do
          if [ -e "$f" ] && [ ! -L "$f" ]; then
            ${pkgs.coreutils}/bin/mv "$f" "$f.pre-hm-$(${pkgs.coreutils}/bin/date +%s)"
          fi
        done
      '';

      ensureClaudeHook = lib.hm.dag.entryAfter ["writeBoundary"] ''
        _settings="${xdgConfigHome}/claude/settings.json"
        if [ ! -f "$_settings" ]; then
          ${pkgs.coreutils}/bin/printf '%s\n' '{}' > "$_settings"
        fi
        if ! jq -e '.hooks.PostToolUse[]? | select(.matcher == "Bash")' "$_settings" > /dev/null 2>&1; then
          _tmp=$(${pkgs.coreutils}/bin/mktemp)
          jq \
            '.hooks.PostToolUse |= (. // []) + [{"matcher":"Bash","hooks":[{"type":"command","command":"AGENT_NAME=claude bash \"''${CLAUDE_CONFIG_DIR:-$HOME/.config/claude}/log-bash.sh\"","async":true}]}]' \
            "$_settings" > "$_tmp" && ${pkgs.coreutils}/bin/mv "$_tmp" "$_settings"
        fi
      '';

      # Register Claude Code marketplaces in ~/.config/claude/settings.json:
      #
      #   nix-config-dev          (local)  — this repo's ai-tools/ directory.
      #                                       Plugin: nix-config-tools.
      #   anthropic-agent-skills  (local)  — upstream anthropics/skills repo
      #                                       checked out by chezmoi to
      #                                       ~/.local/src/ai-tools/anthropic-skills.
      #                                       Plugins: document-skills (docx,
      #                                       pdf, pptx, xlsx) and claude-api.
      #
      # The proprietary docx/pdf/pptx/xlsx skills ship under terms that
      # forbid redistribution outside Anthropic's services, so we never copy
      # them into this repo — we only register the upstream marketplace
      # locally so Claude Code can load them from the chezmoi-managed source.
      #
      # The absolute path for the local marketplace comes from the chezmoi
      # state file written by _record-nix-config-dir, so this wiring tracks
      # the repo even if it gets renamed or moved.  Idempotent: only writes
      # when a key is missing or a path drifted.
      registerClaudeMarketplaces = lib.hm.dag.entryAfter ["ensureClaudeHook" "ensureXdgDirectories"] ''
        _settings="${xdgConfigHome}/claude/settings.json"
        _cm_dir_file="${xdgStateHome}/chezmoi/nix-config-dir"
        if [ ! -f "$_cm_dir_file" ]; then
          exit 0
        fi
        _repo=$(${pkgs.coreutils}/bin/cat "$_cm_dir_file")
        _local_path="$_repo/ai-tools"
        _anthropic_path="${homeDirectory}/.local/src/ai-tools/anthropic-skills"
        if [ ! -d "$_local_path/.claude-plugin" ]; then
          exit 0
        fi
        if [ ! -f "$_settings" ]; then
          ${pkgs.coreutils}/bin/printf '%s\n' '{}' > "$_settings"
        fi

        _local_current=$(jq -r '.extraKnownMarketplaces."nix-config-dev".source.path // ""' "$_settings")
        _local_enabled=$(jq -r '.enabledPlugins."nix-config-tools@nix-config-dev" // false' "$_settings")

        _anthropic_present=false
        if [ -d "$_anthropic_path/.claude-plugin" ]; then
          _anthropic_present=true
        fi
        _anthropic_current=$(jq -r '.extraKnownMarketplaces."anthropic-agent-skills".source.path // ""' "$_settings")
        _doc_enabled=$(jq -r '.enabledPlugins."document-skills@anthropic-agent-skills" // false' "$_settings")
        _api_enabled=$(jq -r '.enabledPlugins."claude-api@anthropic-agent-skills" // false' "$_settings")

        _need_write=false
        if [ "$_local_current" != "$_local_path" ] || [ "$_local_enabled" != "true" ]; then
          _need_write=true
        fi
        if [ "$_anthropic_present" = "true" ] && { [ "$_anthropic_current" != "$_anthropic_path" ] || [ "$_doc_enabled" != "true" ] || [ "$_api_enabled" != "true" ]; }; then
          _need_write=true
        fi
        if [ "$_need_write" = "false" ]; then
          exit 0
        fi

        _tmp=$(${pkgs.coreutils}/bin/mktemp)
        if [ "$_anthropic_present" = "true" ]; then
          jq \
            --arg local "$_local_path" \
            --arg anthropic "$_anthropic_path" \
            '.extraKnownMarketplaces["nix-config-dev"] = {source: {source: "directory", path: $local}}
             | .extraKnownMarketplaces["anthropic-agent-skills"] = {source: {source: "directory", path: $anthropic}}
             | .enabledPlugins["nix-config-tools@nix-config-dev"] = true
             | .enabledPlugins["document-skills@anthropic-agent-skills"] = true
             | .enabledPlugins["claude-api@anthropic-agent-skills"] = true' \
            "$_settings" > "$_tmp" && ${pkgs.coreutils}/bin/mv "$_tmp" "$_settings"
        else
          jq --arg local "$_local_path" \
            '.extraKnownMarketplaces["nix-config-dev"] = {source: {source: "directory", path: $local}}
             | .enabledPlugins["nix-config-tools@nix-config-dev"] = true' \
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
    # Source paths come from copilotInstructionPaths in the let-block above so
    # the orphan-backup activation hook and the deploy targets stay in sync.
    # `force = true` on every entry: home-manager canonically owns these files,
    # and the backupAgentInstructions hook below moves any pre-existing real
    # file aside before write.
    file =
      (lib.genAttrs copilotInstructionPaths (_: {
        source = copilotDefaultsFile;
        force = true;
      }))
      // {
        # Claude Code's memory-file loader hardcodes ~/.claude/CLAUDE.md and
        # does not honor CLAUDE_CONFIG_DIR — see
        # https://code.claude.com/docs/en/memory.md. PR #20 moved this file to
        # the XDG location alone, which silently broke auto-loading. Until
        # Anthropic teaches the loader to follow CLAUDE_CONFIG_DIR (or another
        # XDG-aware mechanism), we deploy the same source to both paths so XDG
        # remains canonical and the legacy path acts as a forwarding pointer
        # the loader can find. Revisit and remove this entry once the upstream
        # fix lands.
        ".claude/CLAUDE.md" = {
          source = claudeDefaultsFile;
          force = true;
        };
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
