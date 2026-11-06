#!/usr/bin/env -S zsh -f
# git-worktree-audit: reports merged vs unmerged worktrees and removes nothing.
emulate -R zsh
setopt err_exit no_unset pipe_fail

repo_root=${0:A:h:h}
source $repo_root/tests/helpers/testlib.zsh
tmp=$(mktemp -d)
trap 'rm -rf -- $tmp' EXIT
test_path=$(system_shell_path $tmp/shim)

git init -q -b main $tmp/repo
git -C $tmp/repo config user.email fixture@example.invalid
git -C $tmp/repo config user.name Fixture
printf base >$tmp/repo/file
git -C $tmp/repo add file
git -C $tmp/repo commit -qm base
git -C $tmp/repo branch merged
git -C $tmp/repo worktree add -q $tmp/merged merged
git -C $tmp/repo branch active
git -C $tmp/repo worktree add -q $tmp/active active
printf change >$tmp/active/new
git -C $tmp/active add new
git -C $tmp/active commit -qm active

audit() { PATH=$test_path $repo_root/chezmoi/dot_local/bin/executable_git-worktree-audit "$@"; }

output=$(audit $tmp/repo --base main)
assert_contains "$output" $tmp/merged
assert_contains "$output" 'merged'
assert_contains "$output" $tmp/active
assert_contains "$output" 'unmerged'
[[ -d $tmp/merged && -d $tmp/active ]] || fail 'audit removed a worktree'

# No --base: the audit defaults to HEAD (the empty-array path under bash 3.2).
output=$(cd $tmp/repo && audit)
assert_contains "$output" $tmp/active
print -r -- 'git-worktree-audit: ok'
