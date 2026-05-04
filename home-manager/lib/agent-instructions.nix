# Renders agent-specific instruction files (Copilot, Claude, ...) from a
# single markdown source. The source uses the placeholder "@@AGENT@@" wherever
# the agent name (e.g. "copilot" or "claude") should appear; this module
# substitutes the placeholder and prepends a YAML frontmatter when requested.
{pkgs}: let
  source = ../../chezmoi/dot_config/instructions/agent-defaults.md;
  body = builtins.readFile source;

  render = {
    agentName,
    withFrontmatter,
    filename,
  }: let
    substituted = builtins.replaceStrings ["@@AGENT@@"] [agentName] body;
    frontmatter = ''
      ---
      description: "Use for every task. Persistent defaults for terminal commands, shell usage, isolated shells for long or heavily quoted commands, and command logging to ~/.cache/${agentName}."
      name: "Persistent Terminal Logging Defaults"
      applyTo: "**"
      ---

    '';
    content =
      if withFrontmatter
      then frontmatter + substituted
      else substituted;
  in
    pkgs.writeText filename content;
in {
  inherit source render;

  copilot = render {
    agentName = "copilot";
    withFrontmatter = true;
    filename = "copilot-defaults.instructions.md";
  };

  claude = render {
    agentName = "claude";
    withFrontmatter = false;
    filename = "CLAUDE.md";
  };
}
