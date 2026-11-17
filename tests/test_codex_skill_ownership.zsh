#!/usr/bin/env -S zsh -f
# Codex skill ownership: the activation validator and the rollback preparer.
# SHELL_UNDER_TEST=bash runs the same cases against a bash version (baseline).
emulate -R zsh
setopt err_exit no_unset pipe_fail

repo_root=${0:A:h:h}
source $repo_root/tests/helpers/testlib.zsh
validator=$repo_root/scripts/validate-codex-skill-target.sh
rollback=$repo_root/scripts/prepare-codex-skill-rollback.sh
tmp=$(mktemp -d)
trap 'rm -rf -- $tmp' EXIT
test_path=$(system_shell_path $tmp/shim)
interp=(zsh -f)
[[ -n ${SHELL_UNDER_TEST-} ]] && interp=($SHELL_UNDER_TEST)

validate() { PATH=$test_path $interp $validator "$@"; }

mkdir -p $tmp/source $tmp/target
print -r -- 'new generation' >$tmp/source/SKILL.md
print -r -- 'old generation' >$tmp/target/SKILL.md

# A manifest is the ownership ledger. Managed content may legitimately differ
# from the new generation during an upgrade.
print -r -- 'git-worktrees' >$tmp/manifest
validate $tmp/source $tmp/target git-worktrees $tmp/manifest

# Marker-owned materialized copies are also safe to replace.
: >$tmp/empty-manifest
: >$tmp/target/.nix-config-managed
validate $tmp/source $tmp/target git-worktrees $tmp/empty-manifest
rm $tmp/target/.nix-config-managed

# An unclaimed but byte-identical legacy copy remains migratable.
cp $tmp/source/SKILL.md $tmp/target/SKILL.md
validate $tmp/source $tmp/target git-worktrees $tmp/empty-manifest

# A genuinely unowned, differing directory must still fail closed.
print -r -- 'independent installation' >$tmp/target/SKILL.md
if validate $tmp/source $tmp/target git-worktrees $tmp/empty-manifest; then
	fail 'unowned differing skill was incorrectly accepted'
fi

# Bad arguments: wrong count is a usage error; a path-like name is refused.
rc=0
validate $tmp/source $tmp/target 2>/dev/null || rc=$?
assert_eq $rc 64
if validate $tmp/source $tmp/target ../escape $tmp/manifest; then
	fail 'a path-like skill name was accepted'
fi

# --- prepare-codex-skill-rollback ---
rollback_run() { XDG_CONFIG_HOME=$tmp/config PATH=$test_path $interp $rollback; }

# No skills directory: nothing to do.
assert_eq "$(rollback_run)" ''

skills=$tmp/config/codex/skills
mkdir -p $skills/plain $skills/.nix-config-skill-backup-alpha
print -r -- 'backed up' >$skills/.nix-config-skill-backup-alpha/SKILL.md
ln -s $skills/.nix-config-skill-backup-alpha $skills/alpha
out=$(rollback_run)
assert_contains "$out" 'restored interrupted Codex skill migration: alpha'
[[ -d $skills/alpha && ! -L $skills/alpha ]] || fail 'alpha was not restored as a directory'
[[ ! -e $skills/.nix-config-skill-backup-alpha ]] || fail 'the backup was left behind'
[[ -d $skills/plain ]] || fail 'a plain directory was touched'
print -r -- 'codex-skill-ownership: ok'
