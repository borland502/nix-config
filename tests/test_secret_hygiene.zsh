#!/usr/bin/env -S zsh -f
# check-secret-hygiene: both rules still catch a leak, and pass a clean tree.
emulate -R zsh
setopt err_exit no_unset pipe_fail

repo_root=${0:A:h:h}
source $repo_root/tests/helpers/testlib.zsh
script=$repo_root/scripts/check-secret-hygiene.sh
tmp=$(mktemp -d)
trap 'rm -rf -- $tmp' EXIT
test_path=$(system_shell_path $tmp/shim)

# Runs the check in directory $1 with age key $2; sets $rc and $err.
check() {
	rc=0
	err=$(cd $1 && SOPS_AGE_KEY_FILE=$2 PATH=$test_path zsh -f $script 2>&1 >/dev/null) || rc=$?
}

# Rule A: the private work tree must hold only encrypted_* files.
mkdir -p $tmp/a/chezmoi/Development/repo
print -r -- 'plain' >$tmp/a/chezmoi/Development/repo/notes.txt
check $tmp/a $tmp/no-such-key
assert_eq $rc 1
assert_contains "$err" 'unencrypted file in the private work tree: chezmoi/Development/repo/notes.txt'
assert_contains "$err" 'skipping the SOPS value scan'
mv $tmp/a/chezmoi/Development/repo/notes.txt $tmp/a/chezmoi/Development/repo/encrypted_notes.txt
check $tmp/a $tmp/no-such-key
assert_eq $rc 0

# Rule B: a SOPS value restated in the clear. The upper-case key exercises the
# case-folded leaf-key match (the ${x,,} expansion bash 3.2 cannot parse).
age-keygen -o $tmp/key.txt 2>/dev/null
pub=$(age-keygen -y $tmp/key.txt)
mkdir -p $tmp/b/secrets $tmp/b/docs
printf '%s\n' 'API_URL: https://leak-host-01.example.test/v1' 'note: harmless-value-xyz' >$tmp/plain.yaml
# An explicit config, so a user-level sops config cannot supply its own rules.
printf '%s\n' 'creation_rules:' "  - age: $pub" >$tmp/sops-config.yaml
sops --config $tmp/sops-config.yaml --encrypt --input-type yaml --output-type yaml $tmp/plain.yaml >$tmp/b/secrets/test.yaml
print -r -- 'see leak-host-01.example.test for details' >$tmp/b/docs/readme.md
print -r -- 'harmless-value-xyz is fine: its key is not a credential' >$tmp/b/docs/other.md
check $tmp/b $tmp/key.txt
assert_eq $rc 1
assert_contains "$err" 'secrets/test.yaml (API_URL) appears in the clear'
assert_contains "$err" 'docs/readme.md:1'
assert_not_contains "$err" 'docs/other.md'
assert_not_contains "$err" 'leak-host-01.example.test'

rm $tmp/b/docs/readme.md
check $tmp/b $tmp/key.txt
assert_eq $rc 0
print -r -- 'secret-hygiene: ok'
