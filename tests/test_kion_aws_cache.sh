#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
root="$(mktemp -d "$repository_root/.test-kion-aws-cache.XXXXXX")"
trap 'rm -rf "$root"' EXIT
fixture_bin="$root/home/.nix-profile/bin"
cache_dir="$root/home/.cache/kion-aws-cache"
trace_file="$root/aws-trace"

mkdir -p "$fixture_bin" "$root/home/.local/bin" "$root/home/.local/lib" "$cache_dir"
cp "$repository_root/chezmoi/dot_local/lib/kion-aws-cache" "$root/home/.local/lib/kion-aws-cache"
cp "$repository_root/chezmoi/dot_local/bin/executable_kac" "$root/home/.local/bin/kac"

reset_stale_cache() {
	printf stale-cache-access >"$cache_dir/AWS_ACCESS_KEY_ID"
	printf stale-cache-secret >"$cache_dir/AWS_SECRET_ACCESS_KEY"
	printf stale-cache-token >"$cache_dir/AWS_SESSION_TOKEN"
	: >"$trace_file"
}

write_refresher() {
	cat >"$fixture_bin/kion-aws-refresh" <<'EOF'
#!/usr/bin/env bash
mkdir -p "$HOME/.cache/kion-aws-cache"
printf fixture-access >"$HOME/.cache/kion-aws-cache/AWS_ACCESS_KEY_ID"
printf fixture-secret >"$HOME/.cache/kion-aws-cache/AWS_SECRET_ACCESS_KEY"
printf fixture-token >"$HOME/.cache/kion-aws-cache/AWS_SESSION_TOKEN"
EOF
	chmod 700 "$fixture_bin/kion-aws-refresh"
}

write_failing_refresher() {
	cat >"$fixture_bin/kion-aws-refresh" <<'EOF'
#!/usr/bin/env bash
exit 23
EOF
	chmod 700 "$fixture_bin/kion-aws-refresh"
}

assert_no_credentials() {
	local output="$1" value
	for value in \
		stale-current-access stale-current-secret stale-current-token \
		stale-cache-access stale-cache-secret stale-cache-token \
		fixture-access fixture-secret fixture-token; do
		if [[ "$output" == *"$value"* ]]; then
			echo "credential value leaked to command output" >&2
			return 1
		fi
	done
}

assert_trace() {
	local expected="$1"
	if [[ "$(<"$trace_file")" != "$expected" ]]; then
		echo "unexpected AWS validation sequence" >&2
		return 1
	fi
}

assert_invocation_count() {
	local expected="$1"
	[[ "$(wc -l <"$trace_file" | tr -d ' ')" -eq "$expected" ]]
}

cat >"$fixture_bin/aws" <<'EOF'
#!/usr/bin/env bash
if [[ "$#" -ne 2 || "$1" != sts || "$2" != get-caller-identity ]]; then
	echo "fixture aws only accepts: aws sts get-caller-identity" >&2
	exit 64
fi

case "${AWS_ACCESS_KEY_ID:-}:${AWS_SECRET_ACCESS_KEY:-}:${AWS_SESSION_TOKEN:-}" in
	stale-current-access:stale-current-secret:stale-current-token)
		printf 'current\n' >>"$AWS_TEST_TRACE"
		exit 1
		;;
	stale-cache-access:stale-cache-secret:stale-cache-token)
		printf 'cached\n' >>"$AWS_TEST_TRACE"
		exit 1
		;;
	fixture-access:fixture-secret:fixture-token)
		printf 'refreshed\n' >>"$AWS_TEST_TRACE"
		exit 0
		;;
	*)
		echo "fixture aws received unexpected credentials" >&2
		exit 65
		;;
esac
EOF
chmod 700 "$fixture_bin/aws"

reset_stale_cache
write_refresher
set +e
success_output="$(
	HOME="$root/home" \
	PATH="$fixture_bin:$PATH" \
	AWS_TEST_TRACE="$trace_file" \
	AWS_ACCESS_KEY_ID=stale-current-access \
	AWS_SECRET_ACCESS_KEY=stale-current-secret \
	AWS_SESSION_TOKEN=stale-current-token \
	bash -c 'source "$HOME/.local/bin/kac" ensure &&
		test "$(<"$AWS_TEST_TRACE")" = $'"'"'current\ncached\nrefreshed'"'"' &&
		test "$AWS_ACCESS_KEY_ID" = fixture-access &&
		test "$AWS_SECRET_ACCESS_KEY" = fixture-secret &&
		test "$AWS_SESSION_TOKEN" = fixture-token' 2>&1
)"
success_status=$?
set -e
[[ "$success_status" -eq 0 ]]
assert_trace $'current\ncached\nrefreshed'
assert_invocation_count 3
assert_no_credentials "$success_output"

reset_stale_cache
rm -f "$fixture_bin/kion-aws-refresh"
set +e
missing_output="$(
	HOME="$root/home" \
	PATH="$fixture_bin:$PATH" \
	AWS_TEST_TRACE="$trace_file" \
	AWS_ACCESS_KEY_ID=stale-current-access \
	AWS_SECRET_ACCESS_KEY=stale-current-secret \
	AWS_SESSION_TOKEN=stale-current-token \
	bash -c 'source "$HOME/.local/bin/kac" ensure
		status=$?
		[[ "$AWS_ACCESS_KEY_ID" = stale-current-access &&
			"$AWS_SECRET_ACCESS_KEY" = stale-current-secret &&
			"$AWS_SESSION_TOKEN" = stale-current-token ]]
		exit "$status"' 2>&1
)"
missing_status=$?
set -e
[[ "$missing_status" -ne 0 ]]
[[ "$missing_output" == *"kion-aws-refresh is not installed"* ]]
assert_trace $'current\ncached'
assert_invocation_count 2
assert_no_credentials "$missing_output"

reset_stale_cache
write_failing_refresher
set +e
failing_output="$(
	HOME="$root/home" \
	PATH="$fixture_bin:$PATH" \
	AWS_TEST_TRACE="$trace_file" \
	AWS_ACCESS_KEY_ID=stale-current-access \
	AWS_SECRET_ACCESS_KEY=stale-current-secret \
	AWS_SESSION_TOKEN=stale-current-token \
	bash -c 'source "$HOME/.local/bin/kac" ensure
		status=$?
		[[ "$AWS_ACCESS_KEY_ID" = stale-current-access &&
			"$AWS_SECRET_ACCESS_KEY" = stale-current-secret &&
			"$AWS_SESSION_TOKEN" = stale-current-token ]]
		exit "$status"' 2>&1
)"
failing_status=$?
set -e
[[ "$failing_status" -ne 0 ]]
[[ "$failing_output" == *"direct Kion credential refresh failed"* ]]
assert_trace $'current\ncached'
assert_invocation_count 2
assert_no_credentials "$failing_output"
