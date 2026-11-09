#!/usr/bin/env -S zsh -f
# The tolerant switch wrappers: what they filter, which failures they downgrade,
# and that every other failure keeps the rebuild's own exit code.
emulate -R zsh
setopt err_exit no_unset pipe_fail

repo_root=${0:A:h:h}
source $repo_root/tests/helpers/testlib.zsh
tmp=$(mktemp -d)
trap 'rm -rf -- $tmp' EXIT
mkdir -p $tmp/bin $tmp/cache
for s in darwin-switch-tolerant nixos-switch-tolerant chezmoi-apply-tolerant; do
	install -m 0755 $repo_root/scripts/$s.sh $tmp/bin/$s
done

# Stubs. sudo passes through. Each rebuild prints $FIXTURE_OUT and exits $FIXTURE_RC.
cat >$tmp/bin/sudo <<'SH'
#!/bin/sh
exec "$@"
SH
for r in darwin-rebuild nixos-rebuild; do
	cat >$tmp/bin/$r <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$TRACE_FILE"
printf '%b' "${FIXTURE_OUT:-}"
exit "${FIXTURE_RC:-0}"
SH
done
# timeout -k 10 300 CMD... -> CMD... ; FIXTURE_TIMEOUT=1 simulates expiry (rc 124).
cat >$tmp/bin/timeout <<'SH'
#!/bin/sh
shift 3
[ -n "${FIXTURE_TIMEOUT:-}" ] && exit 124
exec "$@"
SH
# chezmoi records every call; apply prints $FIXTURE_OUT and exits $FIXTURE_RC.
cat >$tmp/bin/chezmoi <<'SH'
#!/bin/sh
printf 'chezmoi %s\n' "$*" >>"$TRACE_FILE"
case "$1" in apply) printf '%b' "${FIXTURE_OUT:-}"; exit "${FIXTURE_RC:-0}" ;; esac
SH
chmod +x $tmp/bin/*
test_path=$tmp/bin:$(system_shell_path $tmp/shim)

# run NAME RC OUT [ARGS...] -> sets $rc, $out (stdout), $err (stderr)
run() {
	local name=$1 fixture_rc=$2 fixture_out=$3
	shift 3
	: >$tmp/trace
	rc=0
	out=$(FIXTURE_RC=$fixture_rc FIXTURE_OUT=$fixture_out TRACE_FILE=$tmp/trace XDG_CACHE_HOME=$tmp/cache \
		SWITCH_SUDO=$tmp/bin/sudo FIXTURE_TIMEOUT=${FIXTURE_TIMEOUT-} PATH=$test_path $name "$@" 2>$tmp/err) || rc=$?
	err=$(cat -- $tmp/err)
}

orphan='Existing file /x/y.md does not link into a Home Manager generation. Skipping delete.'

# --- darwin-switch-tolerant ---
run darwin-switch-tolerant 0 "activating\n$orphan\ndone\n" .#host
assert_eq $rc 0
assert_contains "$out" 'activating'
assert_not_contains "$out" 'does not link into a Home Manager generation'
assert_file_contains $tmp/trace 'switch --flake .#host'
log=(${(f)"$(print -rl -- $tmp/cache/claude/darwin-switch-*.log)"})
assert_file_contains $log[-1] 'does not link into a Home Manager generation'

run darwin-switch-tolerant 1 "Error: Download failed on Cask 'discord' with message: reset\n" .#host
assert_eq $rc 0
assert_contains "$err" 'only failure was Homebrew'

run darwin-switch-tolerant 1 "Error: Download failed on Cask 'discord'\nerror: builder for '/nix/store/x.drv' failed\n" .#host
assert_eq $rc 1
assert_contains "$err" 'darwin-rebuild failed (exit 1)'

run darwin-switch-tolerant 2 "error: infinite recursion encountered\n" .#host
assert_eq $rc 2

print -r -- "Error: Download failed on Cask 'x'" >$tmp/tolerable.log
run darwin-switch-tolerant 0 '' --classify $tmp/tolerable.log
assert_eq "$rc:$out" '0:tolerate'
print -r -- 'Error: Cask x checksum mismatch' >>$tmp/tolerable.log
run darwin-switch-tolerant 0 '' --classify $tmp/tolerable.log
assert_eq "$rc:$out" '1:propagate'

# --- nixos-switch-tolerant ---
run nixos-switch-tolerant 0 "ok\n" .#wsl
assert_eq $rc 0
assert_file_contains $tmp/trace 'switch --flake .#wsl'

run nixos-switch-tolerant 4 "Failed to open dbus connection\n" .#wsl
assert_eq $rc 0
assert_contains "$err" 'nixos-rebuild returned 4'

run nixos-switch-tolerant 3 "error: something else\n" .#wsl
assert_eq $rc 3
assert_contains "$err" 'nixos-rebuild failed (exit 3)'

# --- chezmoi-apply-tolerant ---
run chezmoi-apply-tolerant 0 "applied\n" $tmp/bin/chezmoi /src
assert_eq $rc 0
assert_file_contains $tmp/trace 'chezmoi init --source /src'
assert_file_contains $tmp/trace 'chezmoi apply --force --keep-going'

run chezmoi-apply-tolerant 1 "chezmoi: .local/src/foo: git clone failed\n" $tmp/bin/chezmoi /src
assert_eq $rc 0
assert_contains "$err" 'chezmoi apply failed (rc=1)'
assert_contains "$err" 'external-related lines'

run chezmoi-apply-tolerant 1 "chezmoi: permission denied writing ~/.zshrc\n" $tmp/bin/chezmoi /src
assert_contains "$err" 'No external is named'

FIXTURE_TIMEOUT=1 run chezmoi-apply-tolerant 0 '' $tmp/bin/chezmoi /src
assert_eq $rc 0
assert_contains "$err" 're-applying without externals'
assert_file_contains $tmp/trace 'apply --force --keep-going --exclude=externals'
print -r -- 'switch-tolerant: ok'
