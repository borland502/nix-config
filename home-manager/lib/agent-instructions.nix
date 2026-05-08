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

  # Generate a Copilot plugin marketplace manifest and per-plugin metadata
  # from the existing ai-tools/skills and ai-tools/agents source trees.
  # Output layout mirrors the awesome-copilot plugin registry format:
  #   marketplace.json          — root registry consumed by `copilot plugin`
  #   skills/<name>/plugin.json — per-skill metadata
  #   agents/<name>/plugin.json — per-agent metadata
  copilotPluginManifestDir =
    pkgs.runCommand "copilot-plugin-manifest" {
      nativeBuildInputs = [pkgs.jq];
    } ''
      mkdir -p "$out"
      skills_root='${../../ai-tools/skills}'
      agents_root='${../../ai-tools/agents}'

      # Extract a scalar value from the first YAML frontmatter block.
      # Strips surrounding single or double quotes from the value.
      extract_field() {
        local field="$1" file="$2"
        awk -v f="$field" '
          /^---/ { found++; next }
          found == 1 && $0 ~ "^" f ": " {
            sub("^" f ": *", "")
            gsub(/^'"'"'|'"'"'$|^"|"$/, "")
            print; exit
          }
          found >= 2 { exit }
        ' "$file"
      }

      marketplace_entries='[]'

      for skill_dir in "$skills_root"/*; do
        [ -d "$skill_dir" ] || continue
        skill_name=$(basename "$skill_dir")
        skill_file="$skill_dir/SKILL.md"
        [ -f "$skill_file" ] || continue

        mkdir -p "$out/skills/$skill_name"
        skill_description=$(extract_field description "$skill_file")

        jq -n \
          --arg name "$skill_name" \
          --arg description "$skill_description" \
          '{name: $name, description: $description, version: "1.0.0",
            skills: [("./skills/" + $name)]}' \
          > "$out/skills/$skill_name/plugin.json"

        marketplace_entries=$(jq -n \
          --argjson existing "$marketplace_entries" \
          --arg name "$skill_name" \
          --arg description "$skill_description" \
          '$existing + [{name: $name,
                          source: ("./skills/" + $name),
                          description: $description,
                          version: "1.0.0",
                          type: "skill"}]')
      done

      for agent_file in "$agents_root"/*.agent.md; do
        [ -f "$agent_file" ] || continue
        agent_name=$(basename "$agent_file" .agent.md)

        mkdir -p "$out/agents/$agent_name"
        agent_description=$(extract_field description "$agent_file")

        jq -n \
          --arg name "$agent_name" \
          --arg description "$agent_description" \
          '{name: $name, description: $description, version: "1.0.0",
            type: "agent",
            tools: ["codebase", "edit/editFiles", "fetch", "search"]}' \
          > "$out/agents/$agent_name/plugin.json"

        marketplace_entries=$(jq -n \
          --argjson existing "$marketplace_entries" \
          --arg name "$agent_name" \
          --arg description "$agent_description" \
          '$existing + [{name: $name,
                          source: ("./agents/" + $name),
                          description: $description,
                          version: "1.0.0",
                          type: "agent"}]')
      done

      jq -n --argjson plugins "$marketplace_entries" \
        '{plugins: $plugins}' > "$out/marketplace.json"
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
