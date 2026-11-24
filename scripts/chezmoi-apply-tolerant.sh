#!/usr/bin/env -S zsh -f
# Initialize and apply with bounded retries and persistent output for each attempt.
emulate -R zsh
setopt no_unset pipe_fail
src=${1:?usage: chezmoi-apply-tolerant.sh source-dir -- executable [args...]}
shift
[[ ${1-} == -- ]] || {
	print -ru2 -- 'expected -- before executable'
	exit 2
}
shift
(($#)) || {
	print -ru2 -- 'missing executable'
	exit 2
}
cmd=("$@")
log_dir=${XDG_CACHE_HOME:-$HOME/.cache}/claude
mkdir -p -- "$log_dir" || exit 1
init_log=$(mktemp "$log_dir/chezmoi-init-XXXXXXXX") || exit 1
print -ru2 -- "chezmoi init log: $init_log"
"${cmd[@]}" init --source "$src" 2>&1 | tee "$init_log"
rc=$pipestatus[1]
((rc == 0)) || exit $rc

apply_log=$(mktemp "$log_dir/chezmoi-apply-XXXXXXXX") || exit 1
print -ru2 -- "chezmoi apply log: $apply_log"
(while true; do
	sleep 8
	print -r -- '    …still applying dotfiles (do not cancel)'
done) >&2 &
hb=$!
trap 'kill $hb 2>/dev/null || true' EXIT
timeout -k 10 300 "${cmd[@]}" apply --force --keep-going 2>&1 | tee "$apply_log"
rc=$pipestatus[1]
kill $hb 2>/dev/null || true
((rc == 0)) && exit 0

# Only a positively identified fetch error or timeout warrants a retry. A
# successful retry is required because keep-going may have encountered other errors.
if ((rc != 124)); then
	# Recognize a Git diagnostic only when accompanied by chezmoi's external
	# path and Git exit status. Reject any other error, including mixed failures.
	if ! awk '
		{
			line = tolower($0)
			if (line ~ /permission denied|template|script|unknown/) bad = 1
			if (line ~ /^fatal: repository .* does not exist$/ || line ~ /^fatal: .* does not appear to be a git repository$/ || line ~ /^fatal: could not read from remote repository\.$/) { git_error = 1; next }
			if (line ~ /^fatal: unable to access .*https:\/\// && (line ~ /could not resolve host: / || line ~ /failed to connect to .*connection timed out$/ || line ~ /the requested url returned error: [0-9][0-9][0-9]$/)) { git_error = 1; next }
			if (line ~ /^fatal: authentication failed for .*https:\/\// || line ~ /^fatal: could not read username for .*https:\/\/.*: terminal prompts disabled$/) { git_error = 1; next }
			if (line ~ /^chezmoi: \.local\/src\/[^:]+: .*: exit status (1|128)$/) { external_status = 1; next }
			if (line ~ /(external|\.local\/src\/).*(git|fetch|clone|pull).*(fail|error)/ || line ~ /(git|fetch|clone|pull).*(fail|error).*(external|\.local\/src\/)/) { identified = 1; next }
			if (line ~ /^chezmoi: / || line ~ /error|fail|denied|cannot|unable|fatal:/) bad = 1
		}
		END { exit !( !bad && (identified || (git_error && external_status)) ) }
	' "$apply_log"; then
		print -ru2 -- "chezmoi apply failed (rc=$rc); see $apply_log"
		exit $rc
	fi
fi
print -ru2 -- 'chezmoi external fetch failed or timed out; re-applying without externals.'
retry_log=$(mktemp "$log_dir/chezmoi-retry-XXXXXXXX") || exit 1
print -ru2 -- "chezmoi retry log: $retry_log"
timeout -k 10 300 "${cmd[@]}" apply --force --keep-going --exclude=externals 2>&1 | tee "$retry_log"
rc=$pipestatus[1]
exit $rc
