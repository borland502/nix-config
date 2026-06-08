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
  # Names of skills currently in ai-tools/skills/ — baked in at eval time so
  # the cleanup activation hook can delete any directory whose name is absent.
  currentSkillNames = builtins.attrNames (builtins.readDir ../ai-tools/skills);
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
  direnvPatched =
    if pkgs.stdenv.isDarwin
    then
      pkgs.direnv.overrideAttrs (old: {
        env = (old.env or {}) // {CGO_ENABLED = "1";};
        doCheck = false;
      })
    else pkgs.direnv;
  # pipx 1.8.0 has test failures in nixos-26.05 due to PEP 508 spacing
  # differences in the packaging library — skip tests, the package itself works.
  pipxPatched = pkgs.pipx.overridePythonAttrs (_old: {
    doCheck = false;
  });
  commonPackages = with pkgs; [
    # Version control
    git
    gh
    gh-dash # TUI dashboard for GitHub PRs/issues
    lazygit # TUI for fast hunk-level staging, diff/log/branch navigation
    delta # syntax-highlighting pager for git diffs (wired as core.pager below)

    # Network
    curl
    wget

    # Build tools
    gcc
    pkg-config
    go-task
    maven

    # Go toolchain
    go
    gopls
    govulncheck
    delve

    # Python
    python3
    pipxPatched
    uv

    # JavaScript
    bun

    # Cloud & AWS
    awscli2
    awslogs
    awsSamCliPatched
    checkov

    # Containers & process management
    docker_29
    docker-buildx
    docker-compose
    overmind

    # Shell enhancement
    bat
    eza
    fzf
    fd
    overmind
    ripgrep
    sd
    zoxide
    direnvPatched

    # Data processing
    jq
    yq-go
    dasel
    gron # flatten JSON into greppable assignment lines (and back)

    # Nix tooling
    alejandra
    statix
    deadnix
    nixd

    # Linters
    markdownlint-cli2
    ruff
    shellcheck
    shfmt
    yamllint
    taplo

    # AI & agent tools
    claude-code
    github-copilot-cli
    opsAgent

    # Secret management
    age
    sops

    # Dotfiles & file sync
    chezmoi
    unison

    # Productivity & content
    glow
    gum
    tealdeer
    scrcpy

    # Basic utilities
    file
    which
    tree
    rsync
    ncdu

    # Compression
    unzip
    p7zip
    zstd

    # System monitoring
    btop
    lsof
  ];
  agentInstructions = import ./lib/agent-instructions.nix {inherit pkgs;};
  inherit (agentInstructions) claude copilot copilotAgentBridgeDir copilotSkillBridgeDir copilotPluginManifestDir;
  # Home-manager-managed agent-instruction destinations (paths relative to $HOME).
  # Single list keeps the home.file refactor and the orphan-backup activation
  # hook below pointing at the same set of files.
  copilotInstructionPaths = [
    ".config/Code/User/prompts/copilot-defaults.instructions.md"
    ".vscode-server/data/User/prompts/copilot-defaults.instructions.md"
    ".config/github-copilot/copilot-defaults.instructions.md"
    ".config/github-copilot/intellij/global-copilot-instructions.md"
  ];
  copilotInstructionDirPaths = [
    ".config/Code/User/prompts/skills"
    ".config/Code/User/prompts/agents"
    ".vscode-server/data/User/prompts/skills"
    ".vscode-server/data/User/prompts/agents"
  ];
  agentInstructionDestPaths =
    [
      "${xdgConfigHome}/claude/CLAUDE.md"
      "${homeDirectory}/.claude/CLAUDE.md"
    ]
    ++ map (p: "${homeDirectory}/${p}") (copilotInstructionPaths ++ copilotInstructionDirPaths);
  opsAgentPython = pkgs.python3.withPackages (ps: [ps.anthropic]);
  opsAgent = pkgs.writeShellScriptBin "ops-agent" ''
    exec ${opsAgentPython}/bin/python ${./scripts/ops-agent.py} "$@"
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
        source = claude;
        force = true;
      };
      # Automation scripts not meant for manual invocation live under
      # ~/.local/bin/ai-tools/ (deployed by chezmoi from
      # chezmoi/dot_local/bin/ai-tools/); only the Copilot hook manifest is
      # generated here. The Claude hook is injected into settings.json by the
      # ensureClaudeHook activation below.
      # Wires Copilot cache/logging hooks. log-bash.sh logs command+output;
      # log-thinking.sh flushes reasoning (data.reasoningText) from the
      # session events.jsonl. postToolUse is the trigger for both — reasoning is
      # written to events.jsonl before a tool completes, so per-tool-call capture
      # catches it. (A turn with reasoning but no tool call is captured on the
      # next tool call; switch to a stop/session-end event if Copilot adds one.)
      "copilot/hooks/log-bash.json".text = builtins.toJSON {
        version = 1;
        hooks.postToolUse = [
          {
            type = "command";
            command = ''AGENT_NAME=copilot exec bash "$HOME/.local/bin/ai-tools/log-bash.sh"'';
            timeoutSec = 10;
          }
          {
            type = "command";
            command = ''AGENT_NAME=copilot bash "$HOME/.local/bin/ai-tools/log-thinking.sh"'';
            timeoutSec = 30;
          }
          {
            type = "command";
            command = ''AGENT_NAME=copilot bash "$HOME/.local/bin/ai-tools/compress-old-cache"'';
            timeoutSec = 20;
          }
        ];
      };

      # Copilot CLI MCP servers, managed declaratively so the set stays lean.
      # Every enabled MCP server injects its tool definitions into context on
      # each agent step — input tokens on every turn under Copilot's
      # usage-based billing. Empty is the leanest default; add a server here
      # only when it's actually needed (e.g. an `aws-api` entry mirroring
      # chezmoi/dot_claude/settings.json, pointing at
      # ~/.local/bin/ai-tools/aws-mcp-server) rather than accumulating
      # always-on servers via interactive `/mcp add`.
      "copilot/mcp-config.json".text = builtins.toJSON {
        mcpServers = {};
      };

      # Single source of truth for custom agent/skill definitions is the
      # top-level ai-tools/ directory (modeled on the obra/superpowers layout).
      # Deploy those definitions into both Claude's and Copilot's XDG config
      # paths so the same plugin content is available to both CLIs.
      # COPILOT_HOME (exported in zsh.nix as $XDG_CONFIG_HOME/copilot)
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
      # Remove skill directories from HM-managed skill paths whose names are no
      # longer in ai-tools/skills/ — orphans left behind by skill renames.
      # currentSkillNames is baked in at eval time so this catches old-generation
      # symlinks too (which the /nix/store/* check would incorrectly keep).
      # Runs before checkLinkTargets so HM doesn't warn about them first.
      cleanupOrphanedSkills = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
        _known=" ${lib.concatStringsSep " " currentSkillNames} "
        for _skills_dir in "${xdgConfigHome}/claude/skills" "${xdgConfigHome}/copilot/skills"; do
          [ -d "$_skills_dir" ] || continue
          for _skill_path in "$_skills_dir"/*/; do
            [ -d "$_skill_path" ] || continue
            _name=$(${pkgs.coreutils}/bin/basename "$_skill_path")
            case "$_known" in
              *" $_name "*) ;;
              *) ${pkgs.coreutils}/bin/rm -rf "$_skill_path" ;;
            esac
          done
        done
      '';

      # Remove stale *.instructions.md files from skill/agent bridge prompt
      # directories.  These were produced by older generations before the bridge
      # generators switched to *.prompt.md; without this hook they persist
      # alongside the new prompt files and re-inflate the instruction count.
      cleanupStaleInstructionBridges = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
        for _dir in ${lib.concatMapStringsSep " " lib.escapeShellArg (
          map (p: "${homeDirectory}/${p}") copilotInstructionDirPaths
        )}; do
          [ -d "$_dir" ] || continue
          for _f in "$_dir"/*.instructions.md; do
            [ -f "$_f" ] || [ -L "$_f" ] || continue
            ${pkgs.coreutils}/bin/rm -f "$_f"
          done
        done
      '';

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
        # Migrate hook command paths from the flat ~/.local/bin/<script> layout to
        # ~/.local/bin/ai-tools/<script> (automation scripts moved into ai-tools/).
        # The add-guards below match on matcher/substring, so they won't rewrite an
        # already-present entry — this self-heals old generations. Idempotent: the
        # regex only matches the pre-move path (no ai-tools/ segment).
        if jq -e '[.. | objects | select(has("command")) | .command | strings | select(test("/\\.local/bin/(log-bash\\.sh|log-thinking\\.sh|compress-old-cache|claude-cache-stats|aws-mcp-server)"))] | length > 0' "$_settings" > /dev/null 2>&1; then
          _tmp=$(${pkgs.coreutils}/bin/mktemp)
          jq '
            walk(
              if type == "object" and (.command? | type) == "string"
              then .command |= gsub("/\\.local/bin/(?<s>log-bash\\.sh|log-thinking\\.sh|compress-old-cache|claude-cache-stats|aws-mcp-server)"; "/.local/bin/ai-tools/\(.s)")
              else . end)
          ' "$_settings" > "$_tmp" && ${pkgs.coreutils}/bin/mv "$_tmp" "$_settings"
        fi
        if ! jq -e '.hooks.PostToolUse[]? | select(.matcher == "Bash")' "$_settings" > /dev/null 2>&1; then
          _tmp=$(${pkgs.coreutils}/bin/mktemp)
          jq \
            '.hooks.PostToolUse |= (. // []) + [{"matcher":"Bash","hooks":[{"type":"command","command":"AGENT_NAME=claude bash \"$HOME/.local/bin/ai-tools/log-bash.sh\"","async":true}]}]' \
            "$_settings" > "$_tmp" && ${pkgs.coreutils}/bin/mv "$_tmp" "$_settings"
        fi
        # SessionEnd: append a one-line prompt-cache summary per session. Fires
        # after the session ends, so it never feeds tokens back into the model.
        if ! jq -e '.hooks.SessionEnd[]? | .hooks[]? | select(.command | test("claude-cache-stats"))' "$_settings" > /dev/null 2>&1; then
          _tmp=$(${pkgs.coreutils}/bin/mktemp)
          jq \
            '.hooks.SessionEnd |= (. // []) + [{"hooks":[{"type":"command","command":"$HOME/.local/bin/ai-tools/claude-cache-stats","async":true}]}]' \
            "$_settings" > "$_tmp" && ${pkgs.coreutils}/bin/mv "$_tmp" "$_settings"
        fi
        # Claude reasoning capture via log-thinking.sh is DISABLED. Claude Code
        # 2.1.69+ stores thinking blocks signature-only (empty text + encrypted
        # signature) in the transcript, so the hook's Claude path can never
        # capture anything — see anthropics/claude-code #31326 / #32810 / #63147.
        # The Copilot path (events.jsonl reasoningText) still works and is wired
        # separately in the Copilot hooks below. Strip any log-thinking entries
        # previously installed under Stop/SubagentStop so old generations are
        # cleaned, and drop hook groups / event keys left empty by the removal.
        if jq -e '.hooks.Stop[]?,.hooks.SubagentStop[]? | .hooks[]? | select((.command // "") | test("log-thinking"))' "$_settings" > /dev/null 2>&1; then
          _tmp=$(${pkgs.coreutils}/bin/mktemp)
          jq '
            reduce ("Stop","SubagentStop") as $e (.;
              .hooks[$e] = ([ .hooks[$e][]?
                              | .hooks |= map(select((.command // "") | test("log-thinking") | not))
                              | select((.hooks | length) > 0) ])
              | if (.hooks[$e] | length) == 0 then del(.hooks[$e]) else . end)
          ' "$_settings" > "$_tmp" && ${pkgs.coreutils}/bin/mv "$_tmp" "$_settings"
        fi
        if ! jq -e '.attribution' "$_settings" > /dev/null 2>&1; then
          _tmp=$(${pkgs.coreutils}/bin/mktemp)
          jq '.attribution = {"commit": "", "pr": ""}' \
            "$_settings" > "$_tmp" && ${pkgs.coreutils}/bin/mv "$_tmp" "$_settings"
        fi
        # skillListingBudgetFraction: fraction of the context window reserved for
        # the skill listing sent to Claude (decimal, not percent; default 0.01 =
        # 1%). Raised to 0.03 (3%) because this repo registers many skills whose
        # combined descriptions overflow the default budget, which silently drops
        # the least-used skills' descriptions and disables their auto-triggers.
        # Self-healing: reconciles to 0.03 whenever the value drifts.
        if [ "$(jq -r '.skillListingBudgetFraction // empty' "$_settings")" != "0.03" ]; then
          _tmp=$(${pkgs.coreutils}/bin/mktemp)
          jq '.skillListingBudgetFraction = 0.03' \
            "$_settings" > "$_tmp" && ${pkgs.coreutils}/bin/mv "$_tmp" "$_settings"
        fi
      '';

      # Copilot CLI default model = "auto": let Copilot route each request to a
      # capability-appropriate model. Under GitHub's usage-based billing (from
      # June 2026) the CLI is token-metered, so the model choice is the primary
      # cost lever. Merged (not overwritten) so Copilot can still persist its
      # other settings; self-healing — reconciles whenever the value drifts.
      # COPILOT_HOME (zsh.nix) points the config dir at ~/.config/copilot.
      ensureCopilotSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
        _settings="${xdgConfigHome}/copilot/settings.json"
        if [ ! -f "$_settings" ]; then
          ${pkgs.coreutils}/bin/mkdir -p "${xdgConfigHome}/copilot"
          ${pkgs.coreutils}/bin/printf '%s\n' '{}' > "$_settings"
        fi
        if [ "$(jq -r '.model // empty' "$_settings")" != "auto" ]; then
          _tmp=$(${pkgs.coreutils}/bin/mktemp)
          jq '.model = "auto"' \
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

      ensureClaudeMcpServers = lib.hm.dag.entryAfter ["ensureClaudeHook"] ''
        _settings="${xdgConfigHome}/claude/settings.json"
        if ! ${pkgs.jq}/bin/jq -e '.mcpServers["awslabs.aws-api-mcp-server"]' "$_settings" > /dev/null 2>&1; then
          _tmp=$(${pkgs.coreutils}/bin/mktemp)
          ${pkgs.jq}/bin/jq \
            '.mcpServers["awslabs.aws-api-mcp-server"] = {
              "command": "uvx",
              "args": ["awslabs.aws-api-mcp-server@latest"],
              "env": {}
            }' \
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

      setDefaultShell = lib.hm.dag.entryAfter ["writeBoundary"] ''
        _zsh="${homeDirectory}/.nix-profile/bin/zsh"
        _username="${config.home.username}"
        if [ -x "$_zsh" ]; then
          if ! ${pkgs.gnugrep}/bin/grep -qxF "$_zsh" /etc/shells 2>/dev/null; then
            ${pkgs.coreutils}/bin/printf '%s\n' "$_zsh" | sudo -n tee -a /etc/shells >/dev/null 2>&1 || true
          fi
          # -n: non-interactive; silently skipped if sudo requires a password.
          # The taskfile's home-switch/upgrade tasks run the same command
          # interactively as a fallback.
          sudo -n /usr/sbin/usermod -s "$_zsh" "$_username" 2>/dev/null || true
        fi
      '';
    };

    # Common packages shared across Linux, WSL, and macOS.
    packages = lib.filter availableOnHost commonPackages;

    # Common home-manager settings
    stateVersion = "26.05";

    # Make Copilot defaults visible to desktop, remote, and shared IDE sessions.
    # Source paths come from copilotInstructionPaths in the let-block above so
    # the orphan-backup activation hook and the deploy targets stay in sync.
    # `force = true` on every entry: home-manager canonically owns these files,
    # and the backupAgentInstructions hook below moves any pre-existing real
    # file aside before write.
    file =
      (lib.genAttrs copilotInstructionPaths (_: {
        source = copilot;
        force = true;
      }))
      // {
        ".config/Code/User/prompts/skills" = {
          source = copilotSkillBridgeDir;
          recursive = true;
          force = true;
        };
        ".config/Code/User/prompts/agents" = {
          source = copilotAgentBridgeDir;
          recursive = true;
          force = true;
        };
        ".vscode-server/data/User/prompts/skills" = {
          source = copilotSkillBridgeDir;
          recursive = true;
          force = true;
        };
        ".vscode-server/data/User/prompts/agents" = {
          source = copilotAgentBridgeDir;
          recursive = true;
          force = true;
        };
        ".config/copilot/plugin-manifest" = {
          source = copilotPluginManifestDir;
          recursive = true;
          force = true;
        };
      }
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
          source = claude;
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

  # Time-based compression of old agent cache files, independent of agent
  # activity. The throttled Stop/postToolUse hooks only fire while an agent is
  # running, so caches could linger uncompressed during long idle stretches.
  # This OS-level timer runs ~daily at zero token cost even when no agent is
  # open; the script's 30-min throttle means it coexists harmlessly with the
  # hooks. AGENT_NAME=copilot targets ~/.cache/copilot (the real dir that
  # ~/.cache/claude symlinks to). Off-minute (03:17) by habit.
  launchd.agents.compress-old-cache = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = ["${xdgBinHome}/ai-tools/compress-old-cache"];
      EnvironmentVariables.AGENT_NAME = "copilot";
      StartCalendarInterval = [
        {
          Hour = 3;
          Minute = 17;
        }
      ];
      StandardOutPath = "${xdgCacheHome}/compress-old-cache.launchd.log";
      StandardErrorPath = "${xdgCacheHome}/compress-old-cache.launchd.log";
    };
  };

  systemd.user = lib.mkIf pkgs.stdenv.isLinux {
    services.compress-old-cache = {
      Unit.Description = "Compress old agent cache files with zstd";
      Service = {
        Type = "oneshot";
        Environment = "AGENT_NAME=copilot";
        ExecStart = "${xdgBinHome}/ai-tools/compress-old-cache";
      };
    };
    timers.compress-old-cache = {
      Unit.Description = "Daily compression of old agent cache files";
      Timer = {
        OnCalendar = "*-*-* 03:17:00";
        Persistent = true;
      };
      Install.WantedBy = ["timers.target"];
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

    # Common Git configuration
    git = {
      enable = true;
      settings = {
        user = {
          name = "jhettenh";
          email = "jhettenh@gmail.com";
        };
        init.defaultBranch = "main";
        core = {
          editor = "vim";
          pager = "delta";
        };
        pull.rebase = false;
        # delta: syntax-highlighted diffs/pager. `delta` package added above.
        interactive.diffFilter = "delta --color-only";
        delta = {
          navigate = true; # n/N to move between diff hunks
          line-numbers = true;
        };
        merge.conflictStyle = "zdiff3";
        diff.colorMoved = "default";
        credential."https://github.com".helper = "!/usr/bin/env gh auth git-credential";
        credential."https://gist.github.com".helper = "!/usr/bin/env gh auth git-credential";
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
      enableBashIntegration = true;
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
