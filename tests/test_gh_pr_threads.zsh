#!/usr/bin/env -S zsh -f
# gh-pr-threads: author filtering, the GraphQL call it delegates, and --json.
emulate -R zsh
setopt err_exit no_unset pipe_fail

repo_root=${0:A:h:h}
source $repo_root/tests/helpers/testlib.zsh
tmp=$(mktemp -d)
trap 'rm -rf -- $tmp' EXIT
mkdir -p $tmp/bin

cat >$tmp/fixture.json <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
  {"isResolved":false,"isOutdated":false,"path":"src/a.ts","line":12,"comments":{"nodes":[{"author":{"login":"alice"},"body":"Please fix","url":"https://example.invalid/a"}]}},
  {"isResolved":true,"isOutdated":false,"path":"src/b.ts","line":4,"comments":{"nodes":[{"author":{"login":"bob"},"body":"Done","url":"https://example.invalid/b"}]}}
]}}}}}
JSON

cat >$tmp/bin/gh <<'SH'
#!/bin/sh
if [ "$1 $2 $3" = "pr view 42" ]; then
	printf '{"number":42,"url":"https://github.com/owner/repo/pull/42"}\n'
	exit 0
fi
exit 64
SH

cat >$tmp/bin/gh-graphql <<'SH'
#!/bin/sh
printf '%s\n' "$@" >"$TRACE_FILE"
cat "$FIXTURE_FILE"
SH
chmod +x $tmp/bin/gh $tmp/bin/gh-graphql

helper=$repo_root/chezmoi/dot_local/bin/executable_gh-pr-threads
data_dir=$repo_root/chezmoi/dot_local/share/gh-pr-threads
run() {
	PATH=$tmp/bin:$PATH TRACE_FILE=$tmp/trace FIXTURE_FILE=$tmp/fixture.json GH_PR_THREADS_DATA_DIR=$data_dir $helper "$@"
}

output=$(run 42 --author alice)
assert_contains "$output" 'src/a.ts:12'
assert_contains "$output" 'alice'
assert_not_contains "$output" 'src/b.ts'
assert_file_contains $tmp/trace 'review-threads.graphql'
assert_file_contains $tmp/trace 'owner=owner'
assert_file_contains $tmp/trace 'repo=repo'
assert_file_contains $tmp/trace 'number=42'

json_output=$(run 42 --all --json)
assert_eq "$(jq length <<<$json_output)" 2
print -r -- 'gh-pr-threads: ok'
