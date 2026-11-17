#!/usr/bin/env bash
# log-skill.sh — PostToolUse hook logger for Skill (slash-command / Agent Skill)
# invocations in Claude Code, Copilot, and Codex.
#
# NOT run by hand. It is wired as a Skill PostToolUse hook in settings.json and
# receives the hook payload as JSON on stdin. For every Skill tool call it
# appends a structured, greppable record to the canonical
# ~/.cache/<agent>/session_<id>.log stream:
#
#   ## [YYYY-MM-DD HH:MM:SS] status=ok event=skill cwd=<dir>
#   CMD: Skill <name> [args]
#   STDOUT:         # only present when the tool response carries text
#   <result, large output truncated>
#   ---
#
# This captures model-initiated (automatic) skill invocations as well as
# user-typed skill slash-commands — anything that runs through the Skill tool.
# Built-in commands like /model or /clear do NOT route through the Skill tool
# and are intentionally not logged here. Mirrors log-bash.sh.
set -euo pipefail

# shellcheck source=chezmoi/dot_local/lib/shell/agent-cache.bash
source "$AGENT_TOOLS_SHELL_LIB/agent-cache.bash"
# shellcheck source=chezmoi/dot_local/lib/shell/hook-log.bash
source "$AGENT_TOOLS_SHELL_LIB/hook-log.bash"

input=$(cat)

# Detect format by Copilot's camelCase "toolName" vs Claude Code's "tool_name".
if printf '%s' "$input" | jq -e '.toolName' >/dev/null 2>&1; then
	# Copilot postToolUse: toolArgs is a JSON string.
	tool_name=$(printf '%s' "$input" | jq -r '.toolName // ""')
	[[ "$tool_name" == "Skill" || "$tool_name" == "skill" ]] || exit 0
	skill=$(printf '%s' "$input" | jq -r '(.toolArgs | fromjson | (.skill // .name)) // ""' 2>/dev/null || echo "")
	args=$(printf '%s' "$input" | jq -r '(.toolArgs | fromjson | .args) // ""' 2>/dev/null || echo "")
	sid=$(printf '%s' "$input" | jq -r '.sessionId // "nosid"')
	cwd=$(printf '%s' "$input" | jq -r '.cwd // .workspaceRoot // ""')
	result=$(printf '%s' "$input" | jq -r '.toolResult.textResultForLlm // ""')
	# Copilot's skill tool often carries no name in toolArgs (observed as
	# `skill=?` records). Recover it from the canonical result line:
	#   Skill "<name>" loaded successfully.
	if [[ -z "$skill" ]]; then
		skill=$(printf '%s' "$result" |
			sed -nE 's/.*Skill "([^"]+)" loaded successfully.*/\1/p' | head -n 1)
	fi
else
	# Claude Code PostToolUse: tool_input is an object {skill, args}.
	tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""')
	[[ "$tool_name" == "Skill" ]] || exit 0
	skill=$(printf '%s' "$input" | jq -r '.tool_input.skill // ""')
	args=$(printf '%s' "$input" | jq -r '.tool_input.args // ""')
	sid=$(printf '%s' "$input" | jq -r '.session_id // "nosid"')
	cwd=$(printf '%s' "$input" | jq -r '.cwd // ""')
	result=$(printf '%s' "$input" | jq -r '
		if (.tool_response | type) == "object" then
			(.tool_response.content // .tool_response.stdout // .tool_response.result // "")
		elif (.tool_response | type) == "string" then .tool_response
		else "" end')
fi

agent=$(agent_cache_normalize "${AGENT_NAME:-claude}")

# Cap very large fields so individual records stay scannable. Character-based
# slicing (no pipe) avoids SIGPIPE under `set -o pipefail`.
max_chars=8000
truncate_field() {
	local data="$1"
	agent_hook_truncate "$data" "$max_chars" "... [truncated $((${#data} - max_chars)) of ${#data} chars — see agent transcript for full output]"
}

log_dir=$(agent_cache_path "$HOME" "$agent")
logfile="$log_dir/session_${sid}.log"
mkdir -p "$log_dir"
agent_hook_record skill ok "$cwd" "Skill ${skill:-?}${args:+ $args}" "$(truncate_field "$result")" "" | agent_hook_append "$logfile"
