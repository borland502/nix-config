#!/usr/bin/env bash
# log-bash.sh — PostToolUse hook logger for Claude Code and Copilot CLI.
#
# NOT run by hand. It is wired as a Bash PostToolUse hook (Claude via
# settings.json, Copilot via ~/.config/copilot/hooks/log-bash.json) and receives
# the hook payload as JSON on stdin. For every Bash/terminal tool call it appends a
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
	case "$tool_name" in
		bash | run_in_terminal | functions.run_in_terminal) ;;
		*) exit 0 ;;
	esac
	cmd=$(printf '%s' "$input" | jq -r '
		if (.toolArgs | type) == "string" then ((.toolArgs | fromjson | .command) // "")
		elif (.toolArgs | type) == "object" then (.toolArgs.command // "")
		else "" end
	' 2>/dev/null || echo "")
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

# Strip benign noise from stderr before deciding status. The hook gets no exit
# code, so any non-empty stderr would otherwise read as a failure — but two
# common lines are not failures:
#   - "Shell cwd was reset to <dir>": Claude Code emits this after a one-shot
#     `cd`, even when the command succeeded.
#   - "...Broken pipe": SIGPIPE from a producer feeding an early-closing
#     consumer (e.g. `... | head`), which is expected, not an error.
# Drop those lines; if nothing substantive remains, treat stderr as empty so
# status falls through to `ok` and no STDERR block is logged. Keep this list
# small and obvious — only add lines that are unambiguously harness noise.
if [[ -n "$stderr" ]]; then
	stderr=$(printf '%s\n' "$stderr" | grep -Eiv 'Shell cwd was reset to |broken pipe' || true)
	[[ -n "${stderr//[[:space:]]/}" ]] || stderr=""
fi

if [[ "$interrupted" == "true" ]]; then
	status="interrupted"
elif [[ -n "$stderr" ]]; then
	status="stderr"
else
	status="ok"
fi

# Cap very large fields so individual records stay scannable. 30000 matches
# Claude Code's own Bash output ceiling, so we log everything the hook is handed
# without loss; output beyond that was already truncated before this hook ran —
# capture it with an explicit `tee` at command time (see agent-defaults.md).
# Character-based slicing (no pipe) avoids SIGPIPE under `set -o pipefail`.
max_chars=30000
truncate_field() {
	local data="$1"
	if ((${#data} > max_chars)); then
		printf '%s\n... [truncated %s of %s chars -- rerun with tee to a ~/.cache file for the full output]' \
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
