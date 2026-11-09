#!/usr/bin/env -S zsh -f
# Regression: gh-graphql must run through its shebang under macOS system shells.
emulate -R zsh
setopt err_exit no_unset pipe_fail

repo_root=${0:A:h:h}
source $repo_root/tests/helpers/testlib.zsh
tmp=$(mktemp -d)
trap 'rm -rf -- $tmp' EXIT
mkdir -p $tmp/bin $tmp/home/.cache/test
install -m 0755 $repo_root/chezmoi/dot_local/bin/executable_gh-graphql $tmp/bin/gh-graphql
cat >$tmp/bin/gh <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$TRACE_FILE"
SH
chmod +x $tmp/bin/gh
print -r -- 'query { viewer { login } }' >$tmp/q.graphql
print -r -- '.data.viewer.login' >$tmp/f.jq
test_path=$tmp/bin:$(system_shell_path $tmp/shim)

run() {
	HOME=$tmp/home AGENT_NAME=test TRACE_FILE=$tmp/trace PATH=$test_path gh-graphql "$@"
}

# No -F and no --jq: both arrays empty (jq_args[@]: unbound variable under bash 3.2).
run probe $tmp/q.graphql 2>/dev/null
last=$(tail -n 1 $tmp/trace)
assert_contains "$last" "api graphql -F query=@$tmp/home/.cache/test/probe-"
assert_not_contains "$last" '--jq'

run probe $tmp/q.graphql --jq $tmp/f.jq -F owner=o 2>/dev/null
last=$(tail -n 1 $tmp/trace)
assert_contains "$last" '-F owner=o --jq .data.viewer.login'

assert_contains "$(run --help 2>&1)" 'gh-graphql <task-tag> <query-file>'
print -r -- 'gh-graphql: ok'
