#!/usr/bin/env bash
set -euo pipefail

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

assert_contains() {
	local haystack="$1" needle="$2"
	[[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

assert_not_contains() {
	local haystack="$1" needle="$2"
	[[ "$haystack" != *"$needle"* ]] || fail "expected output not to contain: $needle"
}

assert_file_contains() {
	local path="$1" needle="$2"
	rg -Fq -- "$needle" "$path" || fail "expected $path to contain: $needle"
}
