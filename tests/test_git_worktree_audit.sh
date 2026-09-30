#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "$repo_root/tests/helpers/testlib.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git init -q -b main "$tmp/repo"
git -C "$tmp/repo" config user.email fixture@example.invalid
git -C "$tmp/repo" config user.name Fixture
printf base >"$tmp/repo/file"
git -C "$tmp/repo" add file
git -C "$tmp/repo" commit -qm base
git -C "$tmp/repo" branch merged
git -C "$tmp/repo" worktree add -q "$tmp/merged" merged
git -C "$tmp/repo" branch active
git -C "$tmp/repo" worktree add -q "$tmp/active" active
printf change >"$tmp/active/new"
git -C "$tmp/active" add new
git -C "$tmp/active" commit -qm active

output="$("$repo_root/chezmoi/dot_local/bin/executable_git-worktree-audit" "$tmp/repo" --base main)"
assert_contains "$output" "$tmp/merged"
assert_contains "$output" 'merged'
assert_contains "$output" "$tmp/active"
assert_contains "$output" 'unmerged'
[[ -d "$tmp/merged" && -d "$tmp/active" ]] || fail 'audit removed a worktree'
