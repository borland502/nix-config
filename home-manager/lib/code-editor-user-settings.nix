{pkgs}: {
  # Fonts consistent with Stylix
  "chat.editor.fontFamily" = "FiraCode Nerd Font Mono";
  "chat.editor.fontSize" = 16.0;
  "chat.fontFamily" = "Inter";
  "debug.console.fontFamily" = "FiraCode Nerd Font Mono";
  "debug.console.fontSize" = 16.0;
  "editor.fontFamily" = "FiraCode Nerd Font Mono";
  "terminal.integrated.fontFamily" = "FiraCode Nerd Font Mono";
  "terminal.integrated.fontSize" = 16.0;
  "terminal.integrated.defaultProfile.linux" = "zsh";
  "terminal.integrated.profiles.linux" = {
    zsh = {
      path = "${pkgs.zsh}/bin/zsh";
      args = ["-l"];
    };
  };

  # Small quality-of-life defaults (non-Stylix)
  "editor.fontSize" = 16.0;
  "editor.fontLigatures" = true;
  "editor.formatOnSave" = true;
  "editor.inlayHints.fontFamily" = "FiraCode Nerd Font Mono";
  "editor.inlineSuggest.fontFamily" = "FiraCode Nerd Font Mono";
  "editor.minimap.sectionHeaderFontSize" = 10.285714285714286;
  "[typescript]" = {
    "editor.formatOnSave" = false;
  };
  "[typescriptreact]" = {
    "editor.formatOnSave" = false;
  };
  "[nix]" = {
    "editor.defaultFormatter" = "jnoortheen.nix-ide";
  };
  "nix.formatterPath" = "alejandra";
  "nix.enableLanguageServer" = true;
  "nix.serverPath" = "nixd";
  "nix.serverSettings" = {
    nixd = {
      formatting.command = ["alejandra"];
    };
  };

  # Go development
  "go.alternateTools" = {
    go = "${pkgs.go}/bin/go";
    gopls = "${pkgs.gopls}/bin/gopls";
    govulncheck = "${pkgs.govulncheck}/bin/govulncheck";
    dlv = "${pkgs.delve}/bin/dlv";
  };
  "go.diagnostic.vulncheck" = "Off";
  "gopls.vulncheck" = "Off";
  "gopls.ui.diagnostic.vulncheck" = "Off";

  # Java development
  "java.configuration.updateBuildConfiguration" = "automatic";
  "java.compile.nullAnalysis.mode" = "automatic";

  "files.trimTrailingWhitespace" = true;
  "files.insertFinalNewline" = true;
  "chat.mcp.access" = "all";
  "chat.mcp.gallery.enabled" = true;
  "chat.tools.urls.autoApprove" = {
    "https://code.visualstudio.com" = true;
    "https://github.com/*" = true;
    "https://*.github.com/*" = true;
    "https://github.com/microsoft/vscode/wiki/*" = true;
    "https://github.com/redhat-developer/vscode-java/wiki/settings-global" = {
      approveRequest = false;
      approveResponse = true;
    };
    "https://*.gov/*" = true;
  };
  "claudeCode.useTerminal" = true;
  "cSpell.enabled" = false;
  "git.blame.editorDecoration.enabled" = true;
  "git.autofetch" = true;
  "markdown.preview.fontFamily" = "Inter";
  "markdown.preview.fontSize" = 16.0;
  "notebook.markup.fontFamily" = "Inter";
  "scm.inputFontFamily" = "FiraCode Nerd Font Mono";
  "scm.inputFontSize" = 14.857142857142858;
  "screencastMode.fontSize" = 64.0;
  "workbench.colorTheme" = "Stylix";

  # VS Code Copilot 0.53+ (shipped in VS Code Insiders on 2026-06-15) moved hook
  # discovery to this VS Code setting. The Copilot CLI still reads the CLI-format
  # manifests in ~/.config/copilot/hooks/ directly; VS Code reads VS Code-format
  # manifests from ~/.copilot/hooks/. The extension resolves keys that start with
  # "~/" against the home directory and *rejects* absolute paths ("glob patterns
  # and absolute paths not supported"), so the tilde form is required here.
  # TODO(mainline-vscode): when VS Code stable ships Copilot ≥ 0.53 this setting
  # will take effect there too — no code change needed, just awareness.
  "chat.hookFilesLocations" = {
    "~/.copilot/hooks" = true;
  };
  # chat.useHooks is the master execution gate and defaults to false — discovered
  # hooks are loaded but never run unless this is on. (chat.useClaudeHooks only
  # gates Claude-format/matcher-wrapped hooks; ours are flat Copilot-format, so it
  # is not required here.)
  "chat.useHooks" = true;
  # Run chat through the Copilot CLI/SDK agent host (provider "copilotcli")
  # instead of the extension-host engine. The CLI backend executes tools in its
  # own process and reads ~/.config/copilot/hooks/ (the path proven to log and to
  # bypass the editor preview-feature org policy). Start a session via the
  # "Chat: New Copilot CLI Session" command (github.copilot.cli.newSession).
  #
  # TODO(native-chat): this agent-host detour exists only because the native
  # extension-host chat hooks (chat.useHooks + chat.hookFilesLocations) are gated
  # by the "Copilot preview features are disabled by organizational policy" block.
  # Once that preview feature is released/allowed for the org, drop
  # chat.agentHost.enabled and go back to the native chat client (the hook
  # settings above already cover it).
  "chat.agentHost.enabled" = true;

  # ---------------------------------------------------------------------------
  # Recovered from ~/.config/Code/User/settings.json.backup (last written
  # 2025-03-01, when home-manager took over programs.vscode and Settings Sync
  # lost the ability to write settings.json). 117 keys existed only in that
  # backup; these are the ones still applicable here.
  #
  # Every per-language binding below was checked against the extension set this
  # config actually installs — a defaultFormatter pointing at a missing
  # extension is a silent "no formatter for this file" error, so bindings for
  # uninstalled extensions were dropped rather than carried over. Deliberately
  # NOT recovered: two plaintext credentials, settings naming paths on machines
  # that no longer exist, and three settings that would fight current config
  # (python.languageServer=Jedi vs Pylance, go.toolsManagement.autoUpdate=true
  # vs the pinned Nix toolchain, workbench.iconTheme vs material-icon-theme).

  # Editor behaviour
  "editor.acceptSuggestionOnEnter" = "on";
  "editor.accessibilitySupport" = "off";
  "editor.defaultFormatter" = "esbenp.prettier-vscode";
  "editor.fontWeight" = "normal";
  "editor.linkedEditing" = true;
  "editor.renderControlCharacters" = false;
  "editor.snippetSuggestions" = "top";
  "editor.suggest.preview" = true;
  "editor.suggest.showMethods" = true;
  "editor.suggestSelection" = "first";
  "editor.tabSize" = 2;
  "diffEditor.codeLens" = true;
  "extensions.ignoreRecommendations" = false;
  "security.workspace.trust.untrustedFiles" = "newWindow";
  "workbench.editor.empty.hint" = "hidden";

  # Git
  "git.enableSmartCommit" = true;
  "git.openRepositoryInParentFolders" = "always";
  "git.terminalAuthentication" = false;

  # Files. The association makes chezmoi's dot_-prefixed shell sources
  # highlight correctly when editing this repo's chezmoi/ tree.
  "files.associations" = {
    dot_zshrc = "shellscript";
  };
  "files.exclude" = {
    "**/.classpath" = true;
    "**/.factorypath" = true;
    "**/.project" = true;
    "**/.settings" = true;
  };

  # Terminal. shellIntegration stays off: it injects prompt markers that mangle
  # captured command output, which this setup relies on staying clean.
  "terminal.integrated.gpuAcceleration" = "on";
  "terminal.integrated.shellIntegration.enabled" = false;

  # Per-language formatters — extension presence verified against the profile
  "[dockerfile]" = {
    "editor.defaultFormatter" = "esbenp.prettier-vscode";
  };
  "[javascript]" = {
    "editor.defaultFormatter" = "vscode.typescript-language-features";
  };
  # Rebound from rvest.vs-code-prettier-eslint, which is not installed.
  "[json]" = {
    "editor.defaultFormatter" = "esbenp.prettier-vscode";
  };
  "[jsonc]" = {
    "editor.defaultFormatter" = "esbenp.prettier-vscode";
  };
  "[markdown]" = {
    "editor.defaultFormatter" = "esbenp.prettier-vscode";
  };
  "[python]" = {
    "editor.defaultFormatter" = "charliermarsh.ruff";
    "editor.formatOnType" = true;
  };
  "[toml]" = {
    "editor.defaultFormatter" = "tamasfe.even-better-toml";
  };
  "[xml]" = {
    "editor.defaultFormatter" = "redhat.vscode-xml";
  };
  "[yaml]" = {
    "editor.defaultFormatter" = "redhat.vscode-yaml";
  };

  # Ruff (charliermarsh.ruff)
  "ruff.configuration" = "pyproject.toml";
  "ruff.enable" = true;
  "ruff.fixAll" = true;
  "ruff.lineLength" = 128;
  "ruff.lint.enable" = true;
  "ruff.organizeImports" = true;

  # TOML (tamasfe.even-better-toml)
  "evenBetterToml.formatter.indentEntries" = true;
  "evenBetterToml.formatter.reorderKeys" = true;

  # YAML (redhat.vscode-yaml) — customTags are the CloudFormation intrinsics
  "yaml.customTags" = [
    "!And"
    "!And sequence"
    "!Base64"
    "!Cidr"
    "!Equals"
    "!Equals sequence"
    "!FindInMap"
    "!FindInMap sequence"
    "!GetAZs"
    "!GetAtt"
    "!If"
    "!If sequence"
    "!ImportValue"
    "!ImportValue sequence"
    "!Join"
    "!Join sequence"
    "!Not"
    "!Not sequence"
    "!Or"
    "!Or sequence"
    "!Ref"
    "!Select"
    "!Select sequence"
    "!Split"
    "!Split sequence"
    "!Sub"
    "!Sub sequence"
  ];
  "yaml.format.printWidth" = 128;
  "yaml.maxItemsComputed" = 10000;

  # Java (redhat.java)
  "java.codeGeneration.hashCodeEquals.useJava7Objects" = true;

  # TypeScript / JavaScript (built-in language features)
  "javascript.experimental.updateImportsOnPaste" = true;
  "javascript.format.semicolons" = "insert";
  "javascript.updateImportsOnFileMove.enabled" = "always";
  "typescript.format.semicolons" = "insert";
  "typescript.tsserver.experimental.enableProjectDiagnostics" = true;
  "typescript.updateImportsOnFileMove.enabled" = "always";

  # Docker (ms-azuretools.vscode-docker). The attach command prefers zsh, then
  # bash, then sh, so exec-ing into a container lands in a usable shell.
  "docker.commands.attach" = "\${config:docker.dockerPath} exec -it \${containerId} sh -c '[ -x \"$(command -v zsh)\" ] && exec zsh || [ -x \"$(command -v bash)\" ] && exec bash || exec sh'";
  "docker.commands.run" = "\${config:docker.dockerPath} run --rm -d \${exposedPorts} \${tag}";
  "docker.commands.runInteractive" = "\${config:docker.dockerPath} run --rm -it \${exposedPorts} \${tag}";
}
