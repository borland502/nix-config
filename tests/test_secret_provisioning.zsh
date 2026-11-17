#!/usr/bin/env -S zsh -f
# The bootstrap's post-Nix scripts: provision-secrets, encrypt-secrets and the
# WSL Windows bootstrap. gum and sops are stubbed; nothing real is written.
# SHELL_UNDER_TEST=bash runs the same cases against a bash version (baseline).
emulate -R zsh
setopt err_exit no_unset pipe_fail

repo_root=${0:A:h:h}
source $repo_root/tests/helpers/testlib.zsh
tmp=$(mktemp -d)
trap 'rm -rf -- $tmp' EXIT
mkdir -p $tmp/bin
interp=(zsh -f)
[[ -n ${SHELL_UNDER_TEST-} ]] && interp=($SHELL_UNDER_TEST)

# gum: style prints its text, input prints $FIXTURE_KEY, confirm exits $FIXTURE_CONFIRM.
cat >$tmp/bin/gum <<'SH'
#!/bin/sh
cmd=$1
shift
case "$cmd" in
style) for a in "$@"; do last=$a; done; printf '%s\n' "$last" ;;
input) printf '%s' "${FIXTURE_KEY:-}" ;;
confirm) exit "${FIXTURE_CONFIRM:-1}" ;;
esac
SH
# sops records its arguments; -d prints a fake decrypted document.
cat >$tmp/bin/sops <<'SH'
#!/bin/sh
printf 'sops %s\n' "$*" >>"$TRACE_FILE"
[ "$1" = -d ] && printf 'ops_agent:\n  jira_token: x\n'
exit 0
SH
chmod +x $tmp/bin/*
test_path=$tmp/bin:$(system_shell_path $tmp/shim)

# run SCRIPT HOME -> $rc, $out (stdout+stderr)
run() {
	local script=$1 home=$2
	: >$tmp/trace
	rc=0
	out=$(HOME=$home TRACE_FILE=$tmp/trace FIXTURE_KEY=${FIXTURE_KEY-} FIXTURE_CONFIRM=${FIXTURE_CONFIRM-} \
		WINDOWS_POWERSHELL_EXE=${WINDOWS_POWERSHELL_EXE-} PATH=$test_path $interp $repo_root/scripts/$script 2>&1) || rc=$?
}

# --- provision-secrets.sh ---
key=$tmp/h1/.config/sops/age/keys.txt
mkdir -p $key:h
print -r -- 'AGE-SECRET-KEY-1EXISTING' >$key
run provision-secrets.sh $tmp/h1
assert_eq $rc 0
assert_contains "$out" 'already present'
assert_eq "$(cat -- $key)" 'AGE-SECRET-KEY-1EXISTING'

FIXTURE_KEY='  AGE-SECRET-KEY-1NEWKEY  ' run provision-secrets.sh $tmp/h2
assert_eq $rc 0
key=$tmp/h2/.config/sops/age/keys.txt
assert_eq "$(cat -- $key)" 'AGE-SECRET-KEY-1NEWKEY'
[[ $(ls -l $key) == -rw-------* ]] || fail "key file mode is not 600: $(ls -l $key)"

FIXTURE_KEY='not-a-key' FIXTURE_CONFIRM=1 run provision-secrets.sh $tmp/h3
assert_eq $rc 1
assert_contains "$out" 'Aborted.'
[[ ! -e $tmp/h3/.config/sops/age/keys.txt ]] || fail 'a rejected key was written'

# --- encrypt-secrets.sh ---
mkdir -p $tmp/h4/.config/ops-agent $tmp/h4/.config/confluence
print -r -- 'jira-tok' >$tmp/h4/.config/ops-agent/jira-token
print -r -- 'conf-tok' >$tmp/h4/.config/confluence/token
run encrypt-secrets.sh $tmp/h4
assert_eq $rc 1
assert_contains "$out" 'base-url not found'
print -r -- 'https://wiki.example.test' >$tmp/h4/.config/confluence/base-url
run encrypt-secrets.sh $tmp/h4
assert_eq $rc 0
yaml=$repo_root/secrets/ops-agent.yaml
assert_file_contains $tmp/trace "sops --set [\"ops_agent\"][\"jira_token\"] \"jira-tok\" $yaml"
assert_file_contains $tmp/trace "sops --set [\"ops_agent\"][\"confluence_base_url\"] \"https://wiki.example.test\" $yaml"
assert_file_contains $tmp/trace "sops --set [\"ops_agent\"][\"confluence_token\"] \"conf-tok\" $yaml"
assert_contains "$out" 'jira_token:'

# --- wsl/bootstrap-windows.sh (early exits; a Mac or plain Linux has no WSL interop) ---
WINDOWS_POWERSHELL_EXE=$tmp/no-such-powershell.exe run wsl/bootstrap-windows.sh $tmp/h5
assert_eq $rc 1
assert_contains "$out" 'Windows PowerShell not found'
if [[ ! -f /proc/sys/fs/binfmt_misc/WSLInterop && ! -f /init ]]; then
	: >$tmp/powershell.exe
	WINDOWS_POWERSHELL_EXE=$tmp/powershell.exe run wsl/bootstrap-windows.sh $tmp/h5
	assert_eq $rc 1
	assert_contains "$out" 'Could not register WSL interop handler'
fi
print -r -- 'secret-provisioning: ok'
