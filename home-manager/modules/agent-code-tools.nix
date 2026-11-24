# Code intelligence, documentation, browser tools and optional skill evaluation.
{
  config,
  lib,
  pkgs,
  ...
}: let
  binHome = "${config.home.homeDirectory}/.local/bin";
  agentToolsLib = (import ../lib/agent-tools-libraries.nix {inherit lib;}).python;
  serena = pkgs.writeShellScript "serena" ''
    exec ${pkgs.uv}/bin/uvx --system-certs --python ${pkgs.python313}/bin/python3 \
      --from 'serena-agent==2.1.0' serena "$@"
  '';
  serenaMcp = pkgs.writeShellScript "serena-mcp" ''
    exec ${serena} start-mcp-server --transport stdio --agent-interface repl \
      --project-from-cwd --enable-web-dashboard false --open-web-dashboard false \
      --enable-gui-log-window false "$@"
  '';
  # Node is scoped to these tools; the interactive shell still uses nvm.
  # Reuse the configured trust bundle without disabling TLS verification.
  nodeEnvironment = ''
    export PATH="${pkgs.nodejs}/bin:$PATH"
    if [ -n "''${SSL_CERT_FILE:-}" ] && [ -z "''${NODE_EXTRA_CA_CERTS:-}" ]; then
      export NODE_EXTRA_CA_CERTS="$SSL_CERT_FILE"
    fi
  '';
  skillgrade = pkgs.writeShellScript "skillgrade" ''
    ${nodeEnvironment}
    exec ${pkgs.nodejs}/bin/npx --yes --package=skillgrade@0.5.0 skillgrade "$@"
  '';
  browserArgs =
    if pkgs.stdenv.isDarwin
    then "--browser chrome"
    else "--browser chrome --executable-path ${pkgs.chromium}/bin/chromium";
  playwrightMcp = pkgs.writeShellScript "playwright-mcp" ''
    ${nodeEnvironment}
    exec ${pkgs.nodejs}/bin/npx --yes --package=@playwright/mcp@0.0.86 playwright-mcp \
      --headless --isolated ${browserArgs} \
      --output-dir "$HOME/.cache/codex/playwright-mcp" "$@"
  '';
  servers = context: {
    serena = {
      command = "${binHome}/serena-mcp";
      args = ["--context" context];
    };
    playwright = {
      command = "${binHome}/playwright-mcp";
      args = [];
    };
    context7.url = "https://mcp.context7.com/mcp";
    aws-knowledge.url = "https://knowledge-mcp.global.api.aws";
  };
  claudeServers = lib.mapAttrs (_: server:
    server
    // {
      type =
        if server ? url
        then "http"
        else "stdio";
    }) (servers "claude-code");
  codexServers = lib.mapAttrs (_: server:
    server
    // {
      startup_timeout_sec = 120;
      tool_timeout_sec = 120;
    }) (servers "codex");
  claudeManifest = pkgs.writeText "claude-managed-mcp.json" (builtins.toJSON claudeServers);
  codexManifest = pkgs.writeText "codex-managed-mcp.json" (builtins.toJSON codexServers);
in {
  home.file = {
    ".local/bin/serena".source = serena;
    ".local/bin/serena-mcp".source = serenaMcp;
    ".local/bin/skillgrade".source = skillgrade;
    ".local/bin/playwright-mcp".source = playwrightMcp;
  };

  # Copilot's external server registry was already managed declaratively.
  xdg.configFile."copilot/mcp-config.json".text = builtins.toJSON {
    mcpServers = lib.mapAttrs (_: server:
      server
      // {
        type =
          if server ? url
          then "http"
          else "local";
        tools = ["*"];
      }) (servers "ide");
  };

  home.activation.ensureAgentMcpClients =
    lib.hm.dag.entryAfter
    (["writeBoundary" "ensureClaudeMcpServers"] ++ lib.optional pkgs.stdenv.isDarwin "linkCodexHome") ''
      export AGENT_TOOLS_LIB=${lib.escapeShellArg agentToolsLib}
      ${pkgs.python3}/bin/python3 ${../../scripts/configure-agent-mcp.py} claude \
        ${lib.escapeShellArg "${config.xdg.configHome}/claude/.claude.json"} ${claudeManifest}
      ${lib.optionalString pkgs.stdenv.isDarwin ''
        if [ ! -d "$HOME/.codex" ] || [ -L "$HOME/.codex" ]; then
          ${pkgs.python3}/bin/python3 ${../../scripts/configure-agent-mcp.py} codex \
            ${lib.escapeShellArg "${config.xdg.configHome}/codex/config.toml"} ${codexManifest}
        fi
      ''}
    '';
}
