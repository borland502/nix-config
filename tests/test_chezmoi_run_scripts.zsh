#!/usr/bin/env -S zsh -f
# Rendered chezmoi run_ scripts that run on macOS: install-go-tools and
# install-agent-clis. Rendered with `chezmoi execute-template`, then run under
# a temporary HOME with stubbed tools, so nothing real is built or installed.
emulate -R zsh
setopt err_exit no_unset pipe_fail

repo_root=${0:A:h:h}
source $repo_root/tests/helpers/testlib.zsh
tmp=$(mktemp -d)
trap 'rm -rf -- $tmp' EXIT
shims=$tmp/shim
test_path=$(system_shell_path $shims)

render() { # render TEMPLATE OUT
	chezmoi execute-template --source $repo_root/chezmoi <$repo_root/chezmoi/$1 >$2
	chmod +x $2
	zsh -f -n $2 || fail "rendered $1 does not parse"
	shfmt -d -i 0 -ln zsh $2 >/dev/null 2>&1 || true # templates keep 2-space indent; parse check only
	shfmt -ln zsh $2 >/dev/null || fail "shfmt cannot parse rendered $1"
}

# --- run_install-go-tools ---
render run_install-go-tools.sh.tmpl $tmp/install-go-tools
home=$tmp/home
mkdir -p $home/.nix-profile/bin $home/.local/src/go-sea
cat >$home/.nix-profile/bin/go <<'SH'
#!/bin/sh
printf 'go %s GOBIN=%s\n' "$*" "$GOBIN" >>"$TRACE_FILE"
: >"$GOBIN/go-sea" && chmod +x "$GOBIN/go-sea"
SH
chmod +x $home/.nix-profile/bin/go
git -C $home/.local/src/go-sea init -q
git -C $home/.local/src/go-sea -c user.email=f@e.invalid -c user.name=F commit -q --allow-empty -m base
sha=$(git -C $home/.local/src/go-sea rev-parse HEAD)

: >$tmp/trace
out=$(HOME=$home TRACE_FILE=$tmp/trace PATH=$test_path $tmp/install-go-tools)
assert_contains "$out" "==> installing go-sea -> $home/.local/bin/go-sea (${sha[1,8]})"
assert_file_contains $tmp/trace "go install . GOBIN=$home/.local/bin"
assert_eq "$(cat -- $home/.local/state/go-tools/go-sea.sha)" $sha

: >$tmp/trace
out=$(HOME=$home TRACE_FILE=$tmp/trace PATH=$test_path $tmp/install-go-tools)
assert_contains "$out" "==> go-sea up to date (${sha[1,8]})"
assert_eq "$(cat -- $tmp/trace)" ''

rm -rf -- $home/.local/src/go-sea
rc=0
out=$(HOME=$home TRACE_FILE=$tmp/trace PATH=$test_path $tmp/install-go-tools 2>&1) || rc=$?
assert_eq $rc 1
assert_contains "$out" 'go-sea is missing'

# --- run_onchange_install-agent-clis ---
render run_onchange_install-agent-clis.sh.tmpl $tmp/install-agent-clis
assert_file_contains $tmp/install-agent-clis 'helper hash: '
out=$(HOME=$tmp/agents-home PATH=$test_path $tmp/install-agent-clis 2>&1)
assert_contains "$out" 'not deployed yet'
mkdir -p $tmp/agents-home/.local/bin
print -rl -- '#!/bin/sh' 'echo update-agent-clis ran' >$tmp/agents-home/.local/bin/update-agent-clis
chmod +x $tmp/agents-home/.local/bin/update-agent-clis
out=$(HOME=$tmp/agents-home PATH=$test_path $tmp/install-agent-clis)
assert_eq "$out" 'update-agent-clis ran'
print -r -- 'chezmoi-run-scripts: ok'
