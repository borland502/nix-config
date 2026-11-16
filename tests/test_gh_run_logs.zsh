#!/usr/bin/env -S zsh -f
# Regression: gh-run-logs must run through its shebang under macOS system shells.
emulate -R zsh
setopt err_exit no_unset pipe_fail

repo_root=${0:A:h:h}
source $repo_root/tests/helpers/testlib.zsh
tmp=$(mktemp -d)
trap 'rm -rf -- $tmp' EXIT
mkdir -p $tmp/bin $tmp/home
install -m 0755 $repo_root/chezmoi/dot_local/bin/executable_gh-run-logs $tmp/bin/gh-run-logs
cat >$tmp/bin/gh <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$TRACE_FILE"
printf 'log line 1\nlog line 2\n'
SH
chmod +x $tmp/bin/gh
test_path=$(system_shell_path $tmp/shim)
test_path=$tmp/bin:$test_path

run() {
	HOME=$tmp/home AGENT_NAME=test TRACE_FILE=$tmp/trace PATH=$test_path gh-run-logs "$@"
}

# No --repo: the empty-array case that failed under bash 3.2 (repo_args[@]: unbound variable).
out=$(run 42 --tail 1)
assert_eq "$(tail -n 1 $tmp/trace)" 'run view 42 --log-failed'
assert_contains "$out" "saved: $tmp/home/.cache/test/run-42-failed.log"
assert_contains "$out" 'log line 2'

out=$(run 42 --repo owner/name --all --tail 0)
assert_eq "$(tail -n 1 $tmp/trace)" 'run view 42 --repo owner/name --log'
assert_not_contains "$out" 'last'

# usage() reads the script's own header, so it must not use $0 inside the function.
assert_contains "$(run --help)" 'Usage: gh-run-logs <run-id>'
print -r -- 'gh-run-logs: ok'
