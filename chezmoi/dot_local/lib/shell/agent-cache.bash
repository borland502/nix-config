# shellcheck shell=bash
# agent_cache_normalize RAW; agent_cache_path BASE NORMALIZED_AGENT
agent_cache_normalize() {
	local agent
	agent=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9._-')
	printf '%s' "${agent:-claude}"
}

agent_cache_path() {
	printf '%s/.cache/%s' "$1" "$2"
}
