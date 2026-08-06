#!/usr/bin/env bash
# Render chezmoi/dot_config/instructions/agent-defaults.md into the per-agent
# instruction copies chezmoi ships to Claude/Copilot.
#
# Shared by `task generate:agent-instructions` (output root: repo root, writes
# the committed copies) and `task check:agent-instructions` (output root: a
# scratch dir, diffed against the committed copies) so the two never drift
# out of sync with each other.
set -euo pipefail

out="${1:?usage: render-agent-instructions.sh <output-root>}"
src="chezmoi/dot_config/instructions/agent-defaults.md"

mkdir -p "$out/chezmoi/dot_config/claude"
sed 's|@@AGENT@@|claude|g' "$src" >"$out/chezmoi/dot_config/claude/CLAUDE.md"

mkdir -p "$out/chezmoi/dot_config/github-copilot/intellij"
mkdir -p "$out/chezmoi/dot_config/Code/User/prompts"
{
	# Plain 'printf -- "---\n"' is ambiguous across shells: go-task's built-in
	# interpreter swallows the "--" and the newline, gluing this onto the next
	# line and corrupting the frontmatter. printf '%s\n' sidesteps that.
	printf '%s\n' '---'
	printf 'description: "Use for every task. Persistent defaults for terminal commands, shell usage, isolated shells for long or heavily quoted commands, and command logging to ~/.cache/copilot."\n'
	printf 'name: "Persistent Terminal Logging Defaults"\n'
	printf 'applyTo: "**"\n'
	printf '%s\n\n' '---'
	sed 's|@@AGENT@@|copilot|g' "$src"
} >"$out/chezmoi/dot_config/github-copilot/copilot-defaults.instructions.md"
cp "$out/chezmoi/dot_config/github-copilot/copilot-defaults.instructions.md" \
	"$out/chezmoi/dot_config/Code/User/prompts/copilot-defaults.instructions.md"
cp "$out/chezmoi/dot_config/github-copilot/copilot-defaults.instructions.md" \
	"$out/chezmoi/dot_config/github-copilot/intellij/global-copilot-instructions.md"

# Repo-root Copilot mirror (no frontmatter); kept in sync by
# check:copilot-instructions via scripts/check-copilot-instructions-sync.sh.
mkdir -p "$out/.github"
sed 's|@@AGENT@@|copilot|g' "$src" >"$out/.github/copilot-instructions.md"
