#!/usr/bin/env -S zsh -f
# Regression: gh-run-logs must run through its shebang under macOS system shells.
emulate -R zsh
setopt err_exit no_unset pipe_fail

repo_root=${0:A:h:h}
source $repo_root/tests/helpers/testlib.zsh
tmp=$(mktemp -d)
trap 'rm -rf -- $tmp' EXIT
mkdir -p $tmp/bin $tmp/home $tmp/lib
install -m 0755 $repo_root/chezmoi/dot_local/bin/executable_gh-run-logs $tmp/bin/gh-run-logs
# Mirror the installed layout: gh-run-logs loads its sibling ../lib/shell.
cp -R $repo_root/chezmoi/dot_local/lib/shell $tmp/lib/shell
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
assert_contains "$(run --help)" 'cancelled or timed-out job'

# Run-state fixtures: 7 in progress with one finished failed job, 8 failed only
# through a cancelled job whose log GitHub did not keep (empty --log-failed;
# the annotation is the only record), 9 in progress with nothing finished,
# 10 completed with no failed jobs, 11 like 8 but with no annotation either.
cat >$tmp/bin/gh <<'SH'
#!/bin/sh
printf '%s|GH_REPO=%s\n' "$*" "${GH_REPO-}" >>"$TRACE_FILE"
case "$*" in
"api repos/{owner}/{repo}/check-runs/202/annotations "*) echo 'failure: The job was not acquired by Runner of type hosted' ;;
"api repos/{owner}/{repo}/check-runs/"*) : ;;
"run view 7 "*"--json jobs"*) printf '101\tfailure\tBuild\n' ;;
"run view 7 "*) echo 'run 7 is still in progress; logs will be available when it is complete'; exit 1 ;;
"api repos/{owner}/{repo}/actions/jobs/101/logs --allow-escape-sequences") printf '\033[31merror: boom\033[0m\n' ;;
"run view 8 "*"--json jobs"*) printf '202\tcancelled\tDarwin Build\n' ;;
"run view 8 "*) : ;;
"api repos/{owner}/{repo}/actions/jobs/202/logs --allow-escape-sequences") echo '<Error><Code>BlobNotFound</Code></Error>'; echo 'gh: HTTP 404' >&2; exit 1 ;;
"run view 9 "*"--json jobs"*) : ;;
"run view 9 "*) echo 'run 9 is still in progress; logs will be available when it is complete'; exit 1 ;;
"run view 10 "*"--json jobs"*) : ;;
"run view 10 "*) : ;;
"run view 11 "*"--json jobs"*) printf '303\tcancelled\tDarwin Build\n' ;;
"run view 11 "*) : ;;
"api repos/{owner}/{repo}/actions/jobs/303/logs --allow-escape-sequences") echo 'gh: HTTP 404' >&2; exit 1 ;;
*) echo "unexpected: $*" >&2; exit 2 ;;
esac
SH
chmod +x $tmp/bin/gh
esc=$'\e'

out=$(run 7 --repo owner/name --tail 5 2>&1)
assert_contains "$out" 'still in progress: saved 1 of 1 finished job(s) only'
assert_contains "$out" "saved: $tmp/home/.cache/test/run-7-failed.log"
assert_file_contains $tmp/home/.cache/test/run-7-failed.log '=== job: Build (failure, id 101) ==='
assert_file_contains $tmp/home/.cache/test/run-7-failed.log 'error: boom'
assert_not_contains "$(cat -- $tmp/home/.cache/test/run-7-failed.log)" $esc
assert_contains "$(cat -- $tmp/trace)" 'actions/jobs/101/logs --allow-escape-sequences|GH_REPO=owner/name'

: >$tmp/trace
out=$(run 8 --tail 5 2>&1)
assert_contains "$out" 'no failed steps; saved 1 non-passing job(s)'
log8=$tmp/home/.cache/test/run-8-failed.log
assert_file_contains $log8 '=== job: Darwin Build (cancelled, id 202) ==='
assert_file_contains $log8 'failure: The job was not acquired by Runner of type hosted'
assert_file_contains $log8 '(no log retained by GitHub for job 202)'
assert_not_contains "$(cat -- $log8)" 'BlobNotFound'
[[ ! -e $log8.part ]] || fail 'the per-job scratch file must be removed'
# No --repo: gh resolves {owner}/{repo} from the checkout, so GH_REPO stays unset.
assert_eq "$(tail -n 1 $tmp/trace)" 'api repos/{owner}/{repo}/actions/jobs/202/logs --allow-escape-sequences|GH_REPO='

rc=0
out=$(run 9 --repo owner/name 2>&1) || rc=$?
assert_eq $rc 1
assert_contains "$out" 'no matching job has finished yet; wait with: monitor-gh-run 9 --repo owner/name'
[[ ! -e $tmp/home/.cache/test/run-9-failed.log ]] || fail 'run 9 must not leave a log file'

rc=0
out=$(run 10 2>&1) || rc=$?
assert_eq $rc 1
assert_contains "$out" 'run 10: no failed jobs (use --all for full logs)'
[[ ! -e $tmp/home/.cache/test/run-10-failed.log ]] || fail 'run 10 must not leave an empty log file'

rc=0
out=$(run 11 2>&1) || rc=$?
assert_eq $rc 1
assert_contains "$out" 'run 11: 1 non-passing job(s), but GitHub kept no log or annotations for them'
[[ ! -e $tmp/home/.cache/test/run-11-failed.log ]] || fail 'run 11 must not leave a header-only log file'
assert_not_contains "$(cat -- $tmp/trace)" 'unexpected'
print -r -- 'gh-run-logs: ok'
