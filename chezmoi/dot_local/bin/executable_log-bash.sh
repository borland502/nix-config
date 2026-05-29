#!/usr/bin/env bash
# log-bash.sh — PostToolUse hook logger for Claude Code and Copilot CLI.
#
# NOT run by hand. It is wired as a Bash PostToolUse hook (Claude via
# settings.json, Copilot via ~/.config/copilot/hooks/log-bash.json) and receives
# the hook payload as JSON on stdin. For every Bash tool call it appends a
# structured, greppable record to ~/.cache/<agent>/session_<id>.log:
#
#   ## [YYYY-MM-DD HH:MM:SS] status=ok|stderr|interrupted cwd=<dir>
#   CMD: <command>
#   STDOUT:
#   <stdout, large output truncated>
#   STDERR:        # only present when stderr is non-empty
#   <stderr>
#   ---
#
# `status` is a heuristic: the hook payload exposes no exit code, so we report
# `interrupted` when the tool was interrupted, else `stderr` when stderr is
# non-empty, else `ok`. cache-scan relies on the `## [...] status=` header line.
set -euo pipefail

input=$(cat)

# Detect format by Copilot's camelCase "toolName" vs Claude Code's "tool_input".
if printf '%s' "$input" | jq -e '.toolName' >/dev/null 2>&1; then
	# Copilot postToolUse: toolArgs is a JSON string; result text is human-readable.
	tool_name=$(printf '%s' "$input" | jq -r '.toolName // ""')
	[[ "$tool_name" == "bash" ]] || exit 0
	cmd=$(printf '%s' "$input" | jq -r '(.toolArgs | fromjson | .command) // ""' 2>/dev/null || echo "")
	sid=$(printf '%s' "$input" | jq -r '.sessionId // "nosid"')
	cwd=$(printf '%s' "$input" | jq -r '.cwd // .workspaceRoot // ""')
	stdout=$(printf '%s' "$input" | jq -r '.toolResult.textResultForLlm // ""')
	stderr=""
	interrupted=$(printf '%s' "$input" | jq -r '.toolResult.interrupted // false')
else
	# Claude Code PostToolUse: tool_input is an object; tool_response is usually
	# an object {stdout,stderr,interrupted,...}, occasionally a bare string.
	tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""')
	[[ -z "$tool_name" || "$tool_name" == "Bash" ]] || exit 0
	cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
	sid=$(printf '%s' "$input" | jq -r '.session_id // "nosid"')
	cwd=$(printf '%s' "$input" | jq -r '.cwd // ""')
	stdout=$(printf '%s' "$input" | jq -r '
		if (.tool_response | type) == "object" then (.tool_response.stdout // "")
		elif (.tool_response | type) == "string" then .tool_response
		else "" end')
	stderr=$(printf '%s' "$input" | jq -r '
		if (.tool_response | type) == "object" then (.tool_response.stderr // "") else "" end')
	interrupted=$(printf '%s' "$input" | jq -r '
		if (.tool_response | type) == "object" then (.tool_response.interrupted // false) else false end')
fi

agent_raw="${AGENT_NAME:-claude}"
agent=$(printf '%s' "$agent_raw" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9._-')
[[ -n "$agent" ]] || agent="claude"

if [[ "$interrupted" == "true" ]]; then
	status="interrupted"
elif [[ -n "$stderr" ]]; then
	status="stderr"
else
	status="ok"
fi

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
logfile="$log_dir/session_${sid}.log"
mkdir -p "$log_dir"

{
	printf '\n## [%s] status=%s cwd=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$status" "${cwd:-?}"
	printf 'CMD: %s\n' "$cmd"
	if [[ -n "$stdout" ]]; then
		printf 'STDOUT:\n%s\n' "$(truncate_field "$stdout")"
	fi
	if [[ -n "$stderr" ]]; then
		printf 'STDERR:\n%s\n' "$(truncate_field "$stderr")"
	fi
	printf -- '---\n'
} >>"$logfile"
