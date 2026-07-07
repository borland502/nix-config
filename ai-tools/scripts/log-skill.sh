#!/usr/bin/env bash
# log-skill.sh — PostToolUse hook logger for Skill (slash-command / Agent Skill)
# invocations in Claude Code (and Copilot).
#
# NOT run by hand. It is wired as a Skill PostToolUse hook in settings.json and
# receives the hook payload as JSON on stdin. For every Skill tool call it
# appends a structured, greppable record to
# ~/.cache/<agent>/session_<id>.skills.log:
#
#   ## [YYYY-MM-DD HH:MM:SS] skill=<name> cwd=<dir>
#   ARGS: <args>
#   RESULT:        # only present when the tool response carries text
#   <result, large output truncated>
#   ---
#
# This captures model-initiated (automatic) skill invocations as well as
# user-typed skill slash-commands — anything that runs through the Skill tool.
# Built-in commands like /model or /clear do NOT route through the Skill tool
# and are intentionally not logged here. Mirrors log-bash.sh.
set -euo pipefail

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

agent_raw="${AGENT_NAME:-claude}"
agent=$(printf '%s' "$agent_raw" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9._-')
[[ -n "$agent" ]] || agent="claude"

# Cap very large fields so individual records stay scannable. Character-based
# slicing (no pipe) avoids SIGPIPE under `set -o pipefail`.
max_chars=8000
truncate_field() {
	local data="$1"
	if ((${#data} > max_chars)); then
		printf '%s\n... [truncated %s of %s chars — see agent transcript for full output]' \
			"${data:0:max_chars}" "$((${#data} - max_chars))" "${#data}"
	else
		printf '%s' "$data"
	fi
}

log_dir="$HOME/.cache/$agent"
logfile="$log_dir/session_${sid}.skills.log"
mkdir -p "$log_dir"

{
	printf '\n## [%s] skill=%s cwd=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${skill:-?}" "${cwd:-?}"
	if [[ -n "$args" ]]; then
		printf 'ARGS: %s\n' "$args"
	fi
	if [[ -n "$result" ]]; then
		printf 'RESULT:\n%s\n' "$(truncate_field "$result")"
	fi
	printf -- '---\n'
} >>"$logfile"
