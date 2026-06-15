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
}
