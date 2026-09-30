#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "$repo_root/tests/helpers/testlib.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat >"$tmp/kac" <<'SH'
if [[ "${1:-}" != ensure ]]; then return 64; fi
printf 'ensure\n' >>"$TRACE_FILE"
export AWS_ACCESS_KEY_ID=fixture
SH

cat >"$tmp/bin/aws" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'aws %s\n' "$*" >>"$TRACE_FILE"
case "$*" in
  *describe-stacks*) printf 'sample-stack\tROLLBACK_COMPLETE\tfixture failure\n' ;;
  *list-stack-resources*) printf 'NestedA\tAWS::CloudFormation::Stack\tchild-stack\tCREATE_FAILED\nBucket\tAWS::S3::Bucket\tbucket-id\tCREATE_FAILED\n' ;;
  *describe-stack-events*) printf '2026-09-30T00:00:00Z\tBucket\tCREATE_FAILED\taccess denied\n' ;;
  *) exit 64 ;;
esac
SH
chmod +x "$tmp/bin/aws"

output="$(TRACE_FILE="$tmp/trace" KAC_PATH="$tmp/kac" AWS_BIN="$tmp/bin/aws" "$repo_root/chezmoi/dot_local/bin/executable_aws-stack-triage" sample-stack --region us-test-1)"
assert_contains "$output" 'ROLLBACK_COMPLETE'
assert_contains "$output" 'child-stack'
assert_contains "$output" 'access denied'
assert_file_contains "$tmp/trace" 'ensure'
assert_file_contains "$tmp/trace" 'describe-stacks'
assert_file_contains "$tmp/trace" 'list-stack-resources'
assert_file_contains "$tmp/trace" 'describe-stack-events'
assert_file_contains "$tmp/trace" '--stack-name child-stack'

summary="$(TRACE_FILE="$tmp/trace" KAC_PATH="$tmp/kac" AWS_BIN="$tmp/bin/aws" "$repo_root/chezmoi/dot_local/bin/executable_aws-stack-triage" sample-stack --summary)"
assert_contains "$summary" 'ROLLBACK_COMPLETE'
assert_not_contains "$summary" 'access denied'
