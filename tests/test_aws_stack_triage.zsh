#!/usr/bin/env -S zsh -f
# aws-stack-triage, run through its shebang under macOS system shells.
emulate -R zsh
setopt err_exit no_unset pipe_fail

repo_root=${0:A:h:h}
source $repo_root/tests/helpers/testlib.zsh
tmp=$(mktemp -d)
trap 'rm -rf -- $tmp' EXIT
mkdir -p $tmp/bin
install -m 0755 $repo_root/chezmoi/dot_local/bin/executable_aws-stack-triage $tmp/bin/aws-stack-triage

cat >$tmp/kac <<'SH'
if [ "${1:-}" != ensure ]; then return 64; fi
printf 'ensure\n' >>"$TRACE_FILE"
export AWS_ACCESS_KEY_ID=fixture
SH

cat >$tmp/bin/aws <<'SH'
#!/bin/sh
printf 'aws %s\n' "$*" >>"$TRACE_FILE"
case "$*" in
*describe-stacks*) printf 'sample-stack\tROLLBACK_COMPLETE\tfixture failure\n' ;;
*list-stack-resources*)
	[ -n "${NO_CHILD:-}" ] || printf 'NestedA\tAWS::CloudFormation::Stack\tchild-stack\tCREATE_FAILED\n'
	printf 'Bucket\tAWS::S3::Bucket\tbucket-id\tCREATE_FAILED\n'
	;;
*describe-stack-events*) printf '2026-09-30T00:00:00Z\tBucket\tCREATE_FAILED\taccess denied\n' ;;
*) exit 64 ;;
esac
SH
chmod +x $tmp/bin/aws
test_path=$tmp/bin:$(system_shell_path $tmp/shim)

run() {
	TRACE_FILE=$tmp/trace KAC_PATH=$tmp/kac AWS_BIN=$tmp/bin/aws PATH=$test_path NO_CHILD=${NO_CHILD-} aws-stack-triage "$@"
}

output=$(run sample-stack --region us-test-1)
assert_contains "$output" 'ROLLBACK_COMPLETE'
assert_contains "$output" 'child-stack'
assert_contains "$output" 'access denied'
assert_file_contains $tmp/trace 'ensure'
assert_file_contains $tmp/trace '--stack-name child-stack --region us-test-1'

summary=$(run sample-stack --summary)
assert_contains "$summary" 'ROLLBACK_COMPLETE'
assert_not_contains "$summary" 'access denied'

# No --region: aws_args is empty (unbound under bash 3.2).
: >$tmp/trace
run sample-stack >/dev/null
assert_not_contains "$(cat -- $tmp/trace)" '--region'

# No nested stacks: child_stacks is empty, and bash 3.2 has no mapfile at all.
output=$(NO_CHILD=1 run sample-stack --region us-test-1)
assert_not_contains "$output" 'CHILD FAILED EVENTS'
print -r -- 'aws-stack-triage: ok'
