#!/usr/bin/env bash
set -euo pipefail

input=$(cat)

# Detect format by presence of Copilot's camelCase "toolName" vs Claude Code's "tool_input".
if printf '%s' "$input" | jq -e '.toolName' >/dev/null 2>&1; then
	# Copilot postToolUse format: toolArgs is a JSON string, result nested under toolResult.
	tool_name=$(printf '%s' "$input" | jq -r '.toolName // ""')
	[[ "$tool_name" == "bash" ]] || exit 0
	cmd=$(printf '%s' "$input" | jq -r '(.toolArgs | fromjson | .command) // ""' 2>/dev/null || echo "")
	sid=$(printf '%s' "$input" | jq -r '.sessionId // "nosid"')
	resp=$(printf '%s' "$input" | jq -r '.toolResult.textResultForLlm // ""')
else
	# Claude Code PostToolUse format: tool_input is an object, tool_response is a string.
	cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
	sid=$(printf '%s' "$input" | jq -r '.session_id // "nosid"')
	resp=$(printf '%s' "$input" | jq -r '
    if .tool_response == null then ""
    elif (.tool_response | type) == "string" then .tool_response
    else .tool_response | tostring
    end')
fi

agent_raw="${AGENT_NAME:-claude}"
agent=$(printf '%s' "$agent_raw" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9._-')
[[ -n "$agent" ]] || agent="claude"

log_dir="$HOME/.cache/$agent"
logfile="$log_dir/session_${sid}.log"
mkdir -p "$log_dir"

{
	printf '\n## [%s]\n' "$(date '+%Y-%m-%d %H:%M:%S')"
	printf 'CMD: %s\n' "$cmd"
	printf 'OUTPUT:\n%s\n' "$resp"
	printf -- '---\n'
} >>"$logfile"
