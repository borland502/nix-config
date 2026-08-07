#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
root="$(mktemp -d "$repository_root/.test-kion-aws-cache.XXXXXX")"
fixture_bin="$root/home/.nix-profile/bin"
cache_dir="$root/home/.cache/kion-aws-cache"
trace_file="$root/aws-trace"
lock_holder_pid=""
lock_ready="$root/cache-lock-ready"
lock_release="$root/cache-lock-release"

cleanup() {
	if [[ -n "$lock_holder_pid" ]] && kill -0 "$lock_holder_pid" 2>/dev/null; then
		: >"$lock_release"
		wait "$lock_holder_pid" || true
	fi
	rm -rf "$root"
}
trap cleanup EXIT

mkdir -p "$fixture_bin" "$root/home/.local/bin" "$root/home/.local/lib" "$cache_dir"
cp "$repository_root/chezmoi/dot_local/lib/kion-aws-cache" "$root/home/.local/lib/kion-aws-cache"
cp "$repository_root/chezmoi/dot_local/lib/kion_aws_cache_lock.py" \
	"$root/home/.local/lib/kion_aws_cache_lock.py"
cp "$repository_root/chezmoi/dot_local/bin/executable_kac" "$root/home/.local/bin/kac"
cp "$repository_root/chezmoi/dot_local/bin/private_executable_kion-aws-cache-lock" \
	"$root/home/.local/bin/kion-aws-cache-lock"
chmod 700 "$root/home/.local/bin/kion-aws-cache-lock"

cat >"$fixture_bin/dirname" <<'EOF'
#!/bin/bash
if [[ "$1" == "--" ]]; then
	shift
fi
printf '%s\n' "${1%/*}"
EOF
chmod 700 "$fixture_bin/dirname"

reset_stale_cache() {
	printf stale-cache-access >"$cache_dir/AWS_ACCESS_KEY_ID"
	printf stale-cache-secret >"$cache_dir/AWS_SECRET_ACCESS_KEY"
	printf stale-cache-token >"$cache_dir/AWS_SESSION_TOKEN"
	: >"$trace_file"
}

reset_generation_cache() {
	local cache_parent="${cache_dir%/*}"
	local cache_name="${cache_dir##*/}"
	local path

	rm -rf "$cache_dir" \
		"$cache_parent/.$cache_name.legacy" \
		"$cache_parent/.$cache_name.pending"
	for path in "$cache_parent/.$cache_name.generation-"*; do
		[[ -e "$path" || -L "$path" ]] && rm -rf "$path"
	done

	stale_generation="$cache_parent/.$cache_name.generation-stale"
	mkdir -p "$stale_generation"
	printf stale-cache-access >"$stale_generation/AWS_ACCESS_KEY_ID"
	printf stale-cache-secret >"$stale_generation/AWS_SECRET_ACCESS_KEY"
	printf stale-cache-token >"$stale_generation/AWS_SESSION_TOKEN"
	ln -s "${stale_generation##*/}" "$cache_dir"
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

write_generation_refresher() {
	cat >"$fixture_bin/kion-aws-refresh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cache_dir="$HOME/.cache/kion-aws-cache"
cache_parent="${cache_dir%/*}"
generation="$cache_parent/.kion-aws-cache.generation-refreshed"

if [[ -e "$cache_dir" || -L "$cache_dir" ]]; then
	exit 24
fi

mkdir -p "$generation"
printf fixture-access >"$generation/AWS_ACCESS_KEY_ID"
printf fixture-secret >"$generation/AWS_SECRET_ACCESS_KEY"
printf fixture-token >"$generation/AWS_SESSION_TOKEN"
ln -s "${generation##*/}" "$cache_dir"
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

write_invalid_cache_refresher() {
	cat >"$fixture_bin/kion-aws-refresh" <<'EOF'
#!/usr/bin/env bash
mkdir -p "$HOME/.cache/kion-aws-cache"
printf invalid-refresh-access >"$HOME/.cache/kion-aws-cache/AWS_ACCESS_KEY_ID"
printf invalid-refresh-secret >"$HOME/.cache/kion-aws-cache/AWS_SECRET_ACCESS_KEY"
printf invalid-refresh-token >"$HOME/.cache/kion-aws-cache/AWS_SESSION_TOKEN"
EOF
	chmod 700 "$fixture_bin/kion-aws-refresh"
}

assert_no_credentials() {
	local output="$1" value
	for value in \
		stale-current-access stale-current-secret stale-current-token \
		stale-cache-access stale-cache-secret stale-cache-token \
		orphan-cache-access orphan-cache-secret orphan-cache-token \
		outside-cache-access outside-cache-secret outside-cache-token \
		fixture-access fixture-secret fixture-token \
		invalid-refresh-access invalid-refresh-secret invalid-refresh-token; do
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

start_cache_lock_holder() {
	local attempt
	rm -f "$lock_ready" "$lock_release"
	python3 - "$cache_dir" "$lock_ready" "$lock_release" <<'PY' &
import fcntl
import os
import pathlib
import sys
import time

cache_dir = pathlib.Path(sys.argv[1])
ready_path = pathlib.Path(sys.argv[2])
release_path = pathlib.Path(sys.argv[3])
lock_path = cache_dir.parent / f".{cache_dir.name}.lock"
descriptor = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
os.fchmod(descriptor, 0o600)
fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
ready_path.touch()
for _ in range(500):
    if release_path.exists():
        break
    time.sleep(0.01)
os.close(descriptor)
PY
	lock_holder_pid=$!

	attempt=0
	while ((attempt < 500)); do
		[[ -e "$lock_ready" ]] && return 0
		kill -0 "$lock_holder_pid" 2>/dev/null || {
			wait "$lock_holder_pid" || true
			echo "cache lock holder exited before acquiring the lock" >&2
			return 1
		}
		sleep 0.01
		attempt=$((attempt + 1))
	done

	echo "cache lock holder did not acquire the lock" >&2
	return 1
}

stop_cache_lock_holder() {
	: >"$lock_release"
	wait "$lock_holder_pid"
	lock_holder_pid=""
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
	invalid-refresh-access:invalid-refresh-secret:invalid-refresh-token)
		printf 'invalid-refreshed\n' >>"$AWS_TEST_TRACE"
		exit 1
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

reset_generation_cache
write_generation_refresher
orphan_generation="${cache_dir%/*}/.kion-aws-cache.generation-orphan"
mkdir -p "$orphan_generation"
printf orphan-cache-access >"$orphan_generation/AWS_ACCESS_KEY_ID"
printf orphan-cache-secret >"$orphan_generation/AWS_SECRET_ACCESS_KEY"
printf orphan-cache-token >"$orphan_generation/AWS_SESSION_TOKEN"
outside_generation="$root/outside-generation"
redirected_generation="${cache_dir%/*}/.kion-aws-cache.generation-redirected"
mkdir -p "$outside_generation"
printf outside-cache-access >"$outside_generation/AWS_ACCESS_KEY_ID"
printf outside-cache-secret >"$outside_generation/AWS_SECRET_ACCESS_KEY"
printf outside-cache-token >"$outside_generation/AWS_SESSION_TOKEN"
ln -s "$outside_generation" "$redirected_generation"
set +e
clear_ensure_output="$(
	HOME="$root/home" \
		PATH="$fixture_bin:$PATH" \
		AWS_TEST_TRACE="$trace_file" \
		AWS_ACCESS_KEY_ID=stale-current-access \
		AWS_SECRET_ACCESS_KEY=stale-current-secret \
		AWS_SESSION_TOKEN=stale-current-token \
		bash -c 'source "$HOME/.local/bin/kac" clear &&
		[[ ! -e "$HOME/.cache/kion-aws-cache" && ! -L "$HOME/.cache/kion-aws-cache" ]] &&
		[[ -z "${AWS_ACCESS_KEY_ID:-}" &&
			-z "${AWS_SECRET_ACCESS_KEY:-}" &&
			-z "${AWS_SESSION_TOKEN:-}" ]] &&
		source "$HOME/.local/bin/kac" ensure &&
		[[ -L "$HOME/.cache/kion-aws-cache" ]] &&
		[[ "$AWS_ACCESS_KEY_ID" = fixture-access &&
			"$AWS_SECRET_ACCESS_KEY" = fixture-secret &&
			"$AWS_SESSION_TOKEN" = fixture-token ]]' 2>&1
)"
clear_ensure_status=$?
set -e
[[ "$clear_ensure_status" -eq 0 ]]
[[ ! -e "$stale_generation" ]]
if [[ -e "$orphan_generation" ]]; then
	echo "clear left an orphan credential generation" >&2
	exit 1
fi
[[ ! -e "$redirected_generation" && ! -L "$redirected_generation" ]]
[[ -d "$outside_generation" ]]
assert_trace "refreshed"
assert_invocation_count 1
assert_no_credentials "$clear_ensure_output"

reset_generation_cache
set +e
dump_output="$(
	HOME="$root/home" \
		PATH="$fixture_bin:$PATH" \
		AWS_TEST_TRACE="$trace_file" \
		AWS_ACCESS_KEY_ID=fixture-access \
		AWS_SECRET_ACCESS_KEY=fixture-secret \
		AWS_SESSION_TOKEN=fixture-token \
		bash -c 'source "$HOME/.local/bin/kac" dump &&
		[[ "$AWS_ACCESS_KEY_ID" = fixture-access &&
			"$AWS_SECRET_ACCESS_KEY" = fixture-secret &&
			"$AWS_SESSION_TOKEN" = fixture-token ]]' 2>&1
)"
dump_status=$?
set -e
[[ "$dump_status" -eq 0 ]]
[[ "$(<"$stale_generation/AWS_ACCESS_KEY_ID")" == fixture-access ]]
[[ "$(<"$stale_generation/AWS_SECRET_ACCESS_KEY")" == fixture-secret ]]
[[ "$(<"$stale_generation/AWS_SESSION_TOKEN")" == fixture-token ]]
assert_trace "refreshed"
assert_invocation_count 1
assert_no_credentials "$dump_output"

if zsh_path="$(command -v zsh 2>/dev/null)"; then
	reset_generation_cache
	set +e
	# shellcheck disable=SC2016  # Expand fixture variables inside zsh.
	zsh_output="$(
		HOME="$root/home" \
			PATH="$fixture_bin:$PATH" \
			AWS_TEST_TRACE="$trace_file" \
			AWS_ACCESS_KEY_ID=fixture-access \
			AWS_SECRET_ACCESS_KEY=fixture-secret \
			AWS_SESSION_TOKEN=fixture-token \
			"$zsh_path" -f -c 'source "$HOME/.local/bin/kac" dump &&
			[[ "$AWS_ACCESS_KEY_ID" = fixture-access &&
				"$AWS_SECRET_ACCESS_KEY" = fixture-secret &&
				"$AWS_SESSION_TOKEN" = fixture-token ]] &&
			source "$HOME/.local/bin/kac" clear &&
			[[ -z "${AWS_ACCESS_KEY_ID:-}" &&
				-z "${AWS_SECRET_ACCESS_KEY:-}" &&
				-z "${AWS_SESSION_TOKEN:-}" ]]' 2>&1
	)"
	zsh_status=$?
	set -e
	if [[ "$zsh_status" -ne 0 ]]; then
		assert_no_credentials "$zsh_output"
		printf 'zsh sourced-shell fixture failed: %s\n' "$zsh_output" >&2
		exit 1
	fi
	[[ ! -e "$cache_dir" && ! -L "$cache_dir" ]]
	[[ ! -e "$stale_generation" ]]
	assert_trace "refreshed"
	assert_invocation_count 1
	assert_no_credentials "$zsh_output"
fi

reset_generation_cache
start_cache_lock_holder
set +e
dump_locked_output="$(
	HOME="$root/home" \
		PATH="$fixture_bin:$PATH" \
		AWS_TEST_TRACE="$trace_file" \
		AWS_ACCESS_KEY_ID=fixture-access \
		AWS_SECRET_ACCESS_KEY=fixture-secret \
		AWS_SESSION_TOKEN=fixture-token \
		bash -c 'source "$HOME/.local/bin/kac" dump' 2>&1
)"
dump_locked_status=$?
set -e
stop_cache_lock_holder
if [[ "$dump_locked_status" -eq 0 ]]; then
	echo "dump mutated the cache while the refresh lock was held" >&2
	exit 1
fi
[[ "$(<"$stale_generation/AWS_ACCESS_KEY_ID")" == stale-cache-access ]]
[[ "$(<"$stale_generation/AWS_SECRET_ACCESS_KEY")" == stale-cache-secret ]]
[[ "$(<"$stale_generation/AWS_SESSION_TOKEN")" == stale-cache-token ]]
assert_trace "refreshed"
assert_invocation_count 1
assert_no_credentials "$dump_locked_output"

reset_generation_cache
contention_orphan="${cache_dir%/*}/.kion-aws-cache.generation-contention-orphan"
mkdir -p "$contention_orphan"
printf orphan-cache-access >"$contention_orphan/AWS_ACCESS_KEY_ID"
printf orphan-cache-secret >"$contention_orphan/AWS_SECRET_ACCESS_KEY"
printf orphan-cache-token >"$contention_orphan/AWS_SESSION_TOKEN"
start_cache_lock_holder
set +e
clear_locked_output="$(
	HOME="$root/home" \
		PATH="$fixture_bin:$PATH" \
		AWS_TEST_TRACE="$trace_file" \
		AWS_ACCESS_KEY_ID=stale-current-access \
		AWS_SECRET_ACCESS_KEY=stale-current-secret \
		AWS_SESSION_TOKEN=stale-current-token \
		bash -c 'source "$HOME/.local/bin/kac" clear
		status=$?
		if [[ "$AWS_ACCESS_KEY_ID" = stale-current-access &&
			"$AWS_SECRET_ACCESS_KEY" = stale-current-secret &&
			"$AWS_SESSION_TOKEN" = stale-current-token ]]; then
			printf "environment=preserved\n"
		fi
		exit "$status"' 2>&1
)"
clear_locked_status=$?
set -e
stop_cache_lock_holder
if [[ "$clear_locked_status" -eq 0 ]]; then
	echo "clear mutated the cache while the refresh lock was held" >&2
	exit 1
fi
[[ "$clear_locked_output" == *"environment=preserved"* ]]
[[ -L "$cache_dir" ]]
[[ "$(<"$stale_generation/AWS_ACCESS_KEY_ID")" == stale-cache-access ]]
[[ "$(<"$stale_generation/AWS_SECRET_ACCESS_KEY")" == stale-cache-secret ]]
[[ "$(<"$stale_generation/AWS_SESSION_TOKEN")" == stale-cache-token ]]
[[ -d "$contention_orphan" ]]
assert_no_credentials "$clear_locked_output"

reset_stale_cache
rm -f "$fixture_bin/kion-aws-refresh"
cat >"$root/missing-refresher-test" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

command() {
	if [[ "$#" -eq 2 && "$1" == "-v" && "$2" == "kion-aws-refresh" ]]; then
		return 1
	fi
	builtin command "$@"
}

aws() {
	if [[ "$#" -ne 2 || "$1" != sts || "$2" != get-caller-identity ]]; then
		return 64
	fi

	case "${AWS_ACCESS_KEY_ID:-}:${AWS_SECRET_ACCESS_KEY:-}:${AWS_SESSION_TOKEN:-}" in
		stale-current-access:stale-current-secret:stale-current-token)
			printf 'current\n' >>"$AWS_TEST_TRACE"
			return 1
			;;
		stale-cache-access:stale-cache-secret:stale-cache-token)
			printf 'cached\n' >>"$AWS_TEST_TRACE"
			return 1
			;;
		*)
			return 65
			;;
	esac
}

set +e
source "$HOME/.local/bin/kac" ensure
status=$?
set -e
[[ "$AWS_ACCESS_KEY_ID" == stale-current-access ]]
[[ "$AWS_SECRET_ACCESS_KEY" == stale-current-secret ]]
[[ "$AWS_SESSION_TOKEN" == stale-current-token ]]
exit "$status"
EOF
chmod 700 "$root/missing-refresher-test"
set +e
missing_output="$(
	env -i \
		HOME="$root/home" \
		USER=fixture-user \
		PATH="$fixture_bin" \
		AWS_TEST_TRACE="$trace_file" \
		AWS_ACCESS_KEY_ID=stale-current-access \
		AWS_SECRET_ACCESS_KEY=stale-current-secret \
		AWS_SESSION_TOKEN=stale-current-token \
		/bin/bash --noprofile --norc "$root/missing-refresher-test" 2>&1
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

reset_stale_cache
write_invalid_cache_refresher
set +e
invalid_cache_output="$(
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
invalid_cache_status=$?
set -e
[[ "$invalid_cache_status" -ne 0 ]]
assert_trace $'current\ncached\ninvalid-refreshed'
assert_invocation_count 3
assert_no_credentials "$invalid_cache_output"
