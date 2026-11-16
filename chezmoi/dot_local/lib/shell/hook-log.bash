# shellcheck shell=bash
# agent_hook_truncate TEXT LIMIT SUFFIX; suffix is appended after a newline.
agent_hook_truncate() {
	local data="$1" limit="$2" suffix="$3"
	if ((${#data} > limit)); then
		printf '%s\n%s' "${data:0:limit}" "$suffix"
	else
		printf '%s' "$data"
	fi
}

# agent_hook_record EVENT STATUS CWD COMMAND STDOUT STDERR
agent_hook_record() {
	printf '\n## [%s] status=%s event=%s cwd=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$2" "$1" "${3:-?}"
	printf 'CMD: %s\n' "$4"
	[[ -z "$5" ]] || printf 'STDOUT:\n%s\n' "$5"
	[[ -z "$6" ]] || printf 'STDERR:\n%s\n' "$6"
	printf -- '---\n'
}

# agent_hook_append FILE reads the record from standard input.
agent_hook_append() (
	umask 077
	cat >>"$1"
	chmod 600 "$1" 2>/dev/null || true
)
