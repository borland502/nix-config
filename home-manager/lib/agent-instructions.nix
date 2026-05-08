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

  # Generate one Copilot prompt file per skill so VS Code prompt discovery can
  # see the same rule content without changing the Claude plugin structure.
  copilotSkillBridgeDir = pkgs.runCommand "copilot-skill-bridge-prompts" {} ''
    mkdir -p "$out"
    skills_root='${../../ai-tools/skills}'

    for skill_dir in "$skills_root"/*; do
      [ -d "$skill_dir" ] || continue
      skill_name=$(basename "$skill_dir")
      skill_file="$skill_dir/SKILL.md"
      [ -f "$skill_file" ] || continue

      out_file="$out/$skill_name.instructions.md"
      {
        printf -- '---\n'
        printf 'description: "Copilot bridge for ai-tools/skills/%s/SKILL.md"\n' "$skill_name"
        printf 'name: "Skill Bridge - %s"\n' "$skill_name"
        printf 'applyTo: "**"\n'
        printf -- '---\n\n'
        printf '# Skill Bridge: %s\n\n' "$skill_name"
        printf 'Source: ai-tools/skills/%s/SKILL.md\n\n' "$skill_name"
        cat "$skill_file"
      } > "$out_file"
    done
  '';

  # Generate one Copilot prompt file per agent so VS Code prompt discovery can
  # apply agent guidance even without first-class agent marketplace support.
  copilotAgentBridgeDir = pkgs.runCommand "copilot-agent-bridge-prompts" {} ''
    mkdir -p "$out"
    agents_root='${../../ai-tools/agents}'

    for agent_file in "$agents_root"/*.agent.md; do
      [ -f "$agent_file" ] || continue
      agent_name=$(basename "$agent_file" .agent.md)
      out_file="$out/$agent_name.instructions.md"

      {
        printf -- '---\n'
        printf 'description: "Copilot bridge for ai-tools/agents/%s.agent.md"\n' "$agent_name"
        printf 'name: "Agent Bridge - %s"\n' "$agent_name"
        printf 'applyTo: "**"\n'
        printf -- '---\n\n'
        printf '# Agent Bridge: %s\n\n' "$agent_name"
        printf 'Source: ai-tools/agents/%s.agent.md\n\n' "$agent_name"
        cat "$agent_file"
      } > "$out_file"
    done
  '';

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
