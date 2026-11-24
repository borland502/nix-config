{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (config.home) homeDirectory;
  xdgBinHome = "${homeDirectory}/.local/bin";
  xdgCacheHome = "${homeDirectory}/.cache";
  xdgConfigHome = "${homeDirectory}/.config";
  xdgStateHome = "${homeDirectory}/.local/state";
  modelTierResolver = import ../lib/model-tier-resolver.nix {inherit pkgs;};
  agentHooks = import ../lib/agent-hooks.nix {inherit xdgBinHome;};
  copilotLogBashHook = agentHooks.copilot "bash";
  copilotLogSkillHook = agentHooks.copilot "skill";
  vscodeCopilotLogBashHook = agentHooks.vscode "bash";
  vscodeCopilotLogSkillHook = agentHooks.vscode "skill";
  # Names of skills currently in ai-tools/skills/ — baked in at eval time so
  # the cleanup activation hook can delete any directory whose name is absent.
  # This is also what evicts the former ai-tools/skills-stack/ tree from hosts
  # that deployed it: those names are gone from the source, so the cleanup hook
  # removes them on the next switch. Pattern borrowed from
  # khaneliman/khanelinix, which keeps the always-on agent surface small.
  currentSkillNames = builtins.attrNames (builtins.readDir ../../ai-tools/skills);
  agentInstructions = import ../lib/agent-instructions.nix {inherit pkgs;};
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
  agentToolsLibraries = import ../lib/agent-tools-libraries.nix {inherit lib;};
  agentToolsLib = agentToolsLibraries.python;
  shellToolsLib = agentToolsLibraries.shell;
  shellToolsNames = ["compress-old-cache" "log-bash.sh" "log-instructions.sh" "log-skill.sh" "log-thinking.sh"];
  shellToolsWrapper = n:
    pkgs.writeShellScript n ''
      export AGENT_TOOLS_SHELL_LIB="''${AGENT_TOOLS_SHELL_LIB:-${shellToolsLib}}"
      exec ${pkgs.bash}/bin/bash ${../../ai-tools/scripts + "/${n}"} "$@"
    '';
  # Python entry point preserves timer/hook invocations through python3 while
  # giving the store-copied collector the same explicit library root as ops-agent.
  agentCacheCapture = pkgs.writeText "agent-cache-capture" ''
    #!/usr/bin/env python3
    import os
    import runpy
    if not os.environ.get("AGENT_TOOLS_LIB"):
        os.environ["AGENT_TOOLS_LIB"] = "${agentToolsLib}"
    runpy.run_path("${../../ai-tools/scripts/agent-cache-capture}", run_name="__main__")
  '';
  # Automation scripts (hook loggers, cache compaction, MCP wrapper) deployed to
  # ~/.local/bin/ai-tools/ from the top-level ai-tools/scripts/ source. Listed
  # explicitly so ops-agent.py (consumed by the writeShellScriptBin above, not a
  # standalone bin) is excluded. executable = true because the bit is forced here
  # rather than relying on the repo file mode.
  aiToolsScriptNames = [
    "agent-cache-capture"
    "aws-mcp-server"
    "bash-habits-hint"
    "claude-cache-stats"
    "compress-old-cache"
    "format-on-edit"
    "log-bash.sh"
    "log-instructions.sh"
    "log-skill.sh"
    "log-thinking.sh"
    "sweep-agent-assets"
    "install-project-skill"
  ];
in {
  xdg = {
    # Generic project templates are data assets, never global skill discovery.
    dataFile."agent-tools/project-skills".source = ../../ai-tools/project-skills;

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
      # Global commit-msg hook: strips Co-authored-by trailers naming Copilot or
      # Claude, the "Generated with Claude Code" line, and Claude-Session
      # trailers, from every locally-made commit. Activated by
      # programs.git.settings.core.hooksPath below. Lives here rather than in a
      # project's .githooks/ because some repos cannot take a committed hook.
      # Human co-authors and prose merely mentioning either tool are preserved.
      #
      # A repo that sets its own core.hooksPath shadows this copy entirely --
      # including THIS one, which does so via `task hooks:install`. Its
      # .githooks/commit-msg is therefore a shim that delegates back to the same
      # script, so the stripper still runs here.
      "git/hooks/commit-msg" = {
        source = ../../ai-tools/git-hooks/commit-msg;
        executable = true;
      };
      # Automation scripts not meant for manual invocation live under
      # ~/.local/bin/ai-tools/ (deployed by home-manager from the top-level
      # ai-tools/scripts/ source — see home.file below); only the Copilot hook
      # manifest is generated here. The Claude hook is injected into
      # settings.json by the ensureClaudeHook activation below.
      # Wires Copilot cache/logging hooks. log-bash.sh logs command+output;
      # log-thinking.sh flushes reasoning (data.reasoningText) from the
      # session events.jsonl. postToolUse is the trigger for both — reasoning is
      # written to events.jsonl before a tool completes, so per-tool-call capture
      # catches it. (A turn with reasoning but no tool call is captured on the
      # next tool call; switch to a stop/session-end event if Copilot adds one.)
      "copilot/hooks/log-bash.json".text = copilotLogBashHook;
      "copilot/hooks/capture.json".source = ../../ai-tools/hooks/copilot-capture.json;

      # Wires the Copilot skill-invocation logger. log-skill.sh self-filters on
      # toolName == "Skill" and appends a canonical record to
      # ~/.cache/copilot/session_<id>.log. Mirrors the Claude PostToolUse
      # "Skill" hook injected by ensureClaudeHook below, so automatic
      # (model-initiated) and slash-command skill calls are tracked for both agents.
      "copilot/hooks/log-skill.json".text = copilotLogSkillHook;

      # Copilot's small external MCP server set is owned by agent-code-tools.

      # Single source of truth for custom agent/skill definitions is the
      # top-level ai-tools/ directory (modeled on the obra/superpowers layout).
      # Token-cost note: every registered skill's description is injected into
      # every session's system prompt, so ai-tools/skills/ is kept to the set
      # that earns that cost. A project needing a stack-specific skill puts it
      # in its own <project>/.claude/skills/, where it loads only there.
      #
      # Claude deliberately does NOT get personal claude/skills or claude/agents
      # dirs: it already loads the same ai-tools content via the nix-config-tools
      # plugin (enabledPlugins in ensureClaudeSettings). Deploying the personal
      # dirs too double-registered every skill AND every agent (clean name +
      # nix-config-tools: name), doubling the listing footprint; for skills that
      # overflowed skillListingBudgetFraction, which silently dropped
      # descriptions and disabled their auto-triggers (agents confirmed
      # double-listed in session context 2026-07-07). Plugin-only keeps the
      # listings lean so auto-invocation fires. Copilot has no plugin system, so
      # it still needs the literal copilot/skills + copilot/agents dirs below.
      # COPILOT_HOME (zsh.nix as $XDG_CONFIG_HOME/copilot) is the parallel of
      # CLAUDE_CONFIG_DIR.
      "copilot/agents" = {
        source = ../../ai-tools/agents;
        recursive = true;
      };
      "copilot/skills" = {
        source = ../../ai-tools/skills;
        recursive = true;
      };
    };
  };
  home.activation = {
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
      AGENT_TOOLS_LIB=${agentToolsLib} AGENT_CAPTURE_MERGER=${../../scripts/merge-agent-capture-hooks.py} \
        ${pkgs.python3}/bin/python3 ${../../scripts/reconcile-claude-settings.py} \
        "${xdgConfigHome}/claude/settings.json" ${../../ai-tools/hooks/claude-capture.json}
    '';

    # Copilot CLI default model: the high tier (sol family). Token budget is
    # not the constraint here, so the session default is the strongest tier;
    # drop down per-role via /model or a mid/low subagent dispatch (role→tier
    # map: agent-reference.md § Model Tiers). The slug floats: the resolver
    # picks the newest listed gpt-<version>-sol from Codex's live catalog and
    # falls back to the lib/model-tiers.nix floor where there is no catalog
    # (Linux/WSL). Copilot and Codex share slugs — gpt-6.1-{sol,terra} and
    # gpt-6-luna verified accepted via `copilot -p --model` 2026-11-24, and an
    # unknown slug fails with "Model ... is not available". Do NOT gate this
    # on `copilot help config` — its model list lags what the backend accepts.
    # Merged (not overwritten) so Copilot can still persist its other
    # settings; self-healing — reconciles whenever the value drifts.
    # COPILOT_HOME (zsh.nix) points the config dir at ~/.config/copilot.
    ensureCopilotSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
      _settings="${xdgConfigHome}/copilot/settings.json"
      ${pkgs.coreutils}/bin/mkdir -p "${xdgConfigHome}/copilot"
      ${modelTierResolver} --catalog ${lib.escapeShellArg "${xdgConfigHome}/codex/models_cache.json"} \
        copilot-settings "$_settings" \
        || echo "ensureCopilotSettings: Copilot model tier left unchanged" >&2
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
    # The body runs in a SUBSHELL because it uses `exit 0` as an early return.
    # Home Manager concatenates every activation snippet into one script, so a
    # bare `exit` there terminates the whole activation — silently, with status
    # 0. That is exactly what happened: once the marketplaces were registered
    # the idempotence check below took its `exit 0` branch on every switch,
    # skipping every later step (seedFlameshotConfig, setDefaultBrowser,
    # setDefaultShell, setupLaunchAgents, vscodeProfiles) and never writing the
    # generation gcroot. No launchd agent added after that point was ever
    # deployed. Keep the parentheses; `exit` inside must not escape them.
    registerClaudeMarketplaces = lib.hm.dag.entryAfter ["ensureClaudeHook" "ensureXdgDirectories"] ''
      (
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
      )
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

    # Enforce ~/.cache/{claude,codex} -> ~/.cache/copilot so every agent shares
    # one log dir. log-bash.sh writes to ~/.cache/$AGENT_NAME, and cache-scan,
    # compress-old-cache and the Drive sync only cover the copilot real dir, so
    # an agent without a link here logs outside that lifecycle. A real dir left
    # by an earlier run is emptied into copilot first, never discarded.
    ensureCacheAgentSymlinks = lib.hm.dag.entryAfter ["ensureXdgDirectories"] ''
      ${pkgs.coreutils}/bin/mkdir -p "${xdgCacheHome}/copilot"
      for agent in claude codex; do
        link="${xdgCacheHome}/$agent"
        if [ -L "$link" ] && [ "$(${pkgs.coreutils}/bin/readlink "$link")" = "${xdgCacheHome}/copilot" ]; then
          continue
        fi
        if [ -d "$link" ] && [ ! -L "$link" ]; then
          ${pkgs.findutils}/bin/find "$link" -mindepth 1 -maxdepth 1 -exec ${pkgs.coreutils}/bin/mv -n {} "${xdgCacheHome}/copilot/" \;
          ${pkgs.coreutils}/bin/rmdir "$link" || {
            echo "ensureCacheAgentSymlinks: $link has entries that collide with copilot; leaving it" >&2
            continue
          }
        fi
        ${pkgs.coreutils}/bin/rm -f "$link"
        ${pkgs.coreutils}/bin/ln -s "${xdgCacheHome}/copilot" "$link"
      done
    '';
  };
  home = {
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
        # VS Code Copilot uses the agent customization hook schema (PostToolUse,
        # timeout), while the Copilot CLI uses ~/.config/copilot/hooks with the
        # CLI schema (postToolUse, timeoutSec). Keep both paths populated.
        ".copilot/hooks/log-bash.json".text = vscodeCopilotLogBashHook;
        ".copilot/hooks/log-skill.json".text = vscodeCopilotLogSkillHook;
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
      }
      // (
        # Deploy the ai-tools automation scripts to ~/.local/bin/ai-tools/ (the
        # path the Claude/Copilot hooks and the compress-old-cache launchd timer
        # invoke). Replaces the former chezmoi deployment now that the source
        # lives in the top-level ai-tools/scripts/ directory.
        builtins.listToAttrs (map (n: {
            name = "${xdgBinHome}/ai-tools/${n}";
            value = {
              source =
                if n == "agent-cache-capture"
                then agentCacheCapture
                else if builtins.elem n shellToolsNames
                then shellToolsWrapper n
                else ../../ai-tools/scripts + "/${n}";
              executable = true;
            };
          })
          aiToolsScriptNames)
      );
  };

  # Time-based compression of old agent cache files, independent of agent
  # activity. The throttled Stop/postToolUse hooks only fire while an agent is
  # running, so caches could linger uncompressed during long idle stretches.
  # This OS-level timer runs ~daily at zero token cost even when no agent is
  # open; the script's 30-min throttle means it coexists harmlessly with the
  # hooks. AGENT_NAME=copilot targets ~/.cache/copilot (the real dir that
  # ~/.cache/claude symlinks to). Off-minute (03:17) by habit.
  launchd.agents = {
    agent-cache-capture = lib.mkIf pkgs.stdenv.isDarwin {
      enable = true;
      config = {
        ProgramArguments = ["${pkgs.python3}/bin/python3" "${xdgBinHome}/ai-tools/agent-cache-capture" "--reconcile"];
        EnvironmentVariables = {
          HOME = homeDirectory;
          XDG_CACHE_HOME = xdgCacheHome;
          XDG_CONFIG_HOME = xdgConfigHome;
        };
        RunAtLoad = true;
        StartInterval = 900;
        ProcessType = "Background";
        StandardOutPath = "${xdgCacheHome}/copilot/agent-capture-timer.log";
        StandardErrorPath = "${xdgCacheHome}/copilot/agent-capture-timer.log";
        Umask = 63;
      };
    };
    compress-old-cache = lib.mkIf pkgs.stdenv.isDarwin {
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
  };

  systemd.user = lib.mkIf pkgs.stdenv.isLinux {
    services.agent-cache-capture = {
      Unit = {
        Description = "Mirror native agent transcripts and artifacts into the cache";
        ConditionFileIsExecutable = "${xdgBinHome}/ai-tools/agent-cache-capture";
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.python3}/bin/python3 ${xdgBinHome}/ai-tools/agent-cache-capture --reconcile";
        Environment = ["HOME=${homeDirectory}" "XDG_CACHE_HOME=${xdgCacheHome}" "XDG_CONFIG_HOME=${xdgConfigHome}"];
        StandardOutput = "append:${xdgCacheHome}/copilot/agent-capture-timer.log";
        StandardError = "append:${xdgCacheHome}/copilot/agent-capture-timer.log";
        UMask = "0077";
      };
    };
    timers.agent-cache-capture = {
      Unit.Description = "Reconcile agent capture every fifteen minutes";
      Timer = {
        OnBootSec = "2m";
        OnUnitInactiveSec = "15m";
      };
      Install.WantedBy = ["timers.target"];
    };
    services.compress-old-cache = {
      Unit = {
        Description = "Compress old agent cache files with zstd";
        # ExecStart is a $HOME path, not a store path, so systemd has no
        # dependency on the thing it runs and would just fail if it were
        # missing. Home Manager's own linkGeneration deploys this one, so it is
        # normally present — but the unit should still stand down cleanly rather
        # than log a failure on a host mid-provision. Same guard, same reason as
        # modules/gdrive-sync.nix.
        ConditionFileIsExecutable = "${xdgBinHome}/ai-tools/compress-old-cache";
      };
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
    # No kion-aws-refresh unit here on purpose: Kion credentials are only used
    # from the darwin host, and the launchd.agents.kion-aws-refresh above
    # already covers it.  A systemd copy here just fails every four hours on
    # Linux hosts that have no Kion setup, degrading the user session.
  };
}
