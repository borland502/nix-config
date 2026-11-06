#!/usr/bin/env -S zsh -f
# Small ~/.local/bin helpers, each run through its shebang under the system
# shells with stubbed tools: nothing touches the network, sudo or the login shell.
# Not covered: update-agent-clis's Darwin-only Codex branch (absolute /usr/bin/curl).
emulate -R zsh
setopt err_exit no_unset pipe_fail

repo_root=${0:A:h:h}
source $repo_root/tests/helpers/testlib.zsh
src=$repo_root/chezmoi/dot_local/bin
tmp=$(mktemp -d)
trap 'rm -rf -- $tmp' EXIT
shims=$tmp/shim
system_shell_path $shims >/dev/null

# stubdir NAME -> a directory holding the shell shims and basic text tools only:
# no package manager, curl, rclone or sudo unless a test stubs one in.
base_tools=(cat grep sed tr head tail mkdir date sleep cut wc)
stubdir() {
	local dir=$tmp/path-$1 t
	mkdir -p $dir
	ln -sf $shims/*(N) $dir/
	for t in $base_tools; do ln -sf $(command -v $t) $dir/$t; done
	print -r -- $dir
}
stub() { # stub DIR NAME BODY
	print -r -- '#!/bin/sh' >$1/$2
	print -r -- $3 >>$1/$2
	chmod +x $1/$2
}
# run DIR-PATH HELPER ARGS... -> $rc, $out (stdout+stderr), stdin closed
run() {
	local p=$1 helper=$2
	shift 2
	rc=0
	out=$(PATH=$p TRACE_FILE=$tmp/trace $helper "$@" </dev/null 2>&1) || rc=$?
}
install_helper() { install -m 0755 $src/executable_$1 $tmp/bin/$1; }
mkdir -p $tmp/bin
: >$tmp/trace

# --- monitor-gh-run: execs the sibling gh-wait-job with the same arguments ---
mkdir -p $tmp/mon
install -m 0755 $src/executable_monitor-gh-run $tmp/mon/monitor-gh-run
stub $tmp/mon gh-wait-job 'printf "wait-job %s\n" "$*"'
run $tmp/mon:$shims:$PATH $tmp/mon/monitor-gh-run 123 --job Deploy
assert_eq $rc 0
assert_eq "$out" 'wait-job 123 --job Deploy'
mv $tmp/mon/gh-wait-job $tmp/mon/executable_gh-wait-job
run $tmp/mon:$shims:$PATH $tmp/mon/monitor-gh-run 456
assert_eq "$out" 'wait-job 456'

# --- pkg-install: refuses what it cannot confirm, installs what it can ---
install_helper pkg-install
p=$(stubdir pkg)
stub $p brew 'printf "brew %s\n" "$*" >>"$TRACE_FILE"; [ "$1" = info ] && case "$*" in *good*) exit 0 ;; *) exit 1 ;; esac; exit 0'
run $p $tmp/bin/pkg-install
assert_eq $rc 1
assert_contains "$out" 'Usage: pkg-install'
run $p $tmp/bin/pkg-install --help
assert_eq $rc 0
run $p $tmp/bin/pkg-install good bad
assert_eq $rc 1
assert_contains "$out" 'could not confirm: bad'
assert_not_contains "$(cat -- $tmp/trace)" 'brew install'
run $p $tmp/bin/pkg-install good
assert_eq $rc 0
assert_file_contains $tmp/trace 'brew install -- good'
run $(stubdir none) $tmp/bin/pkg-install good
assert_eq $rc 1
assert_contains "$out" 'no supported package manager found'

# --- ensure-nix-zsh-shell: never changes the shell without sudo or a TTY ---
install_helper ensure-nix-zsh-shell
p=$(stubdir ensure)
stub $p sudo 'printf "sudo %s\n" "$*" >>"$TRACE_FILE"; exit 1'
stub $p usermod 'printf "usermod %s\n" "$*" >>"$TRACE_FILE"'
stub $p chsh 'printf "chsh %s\n" "$*" >>"$TRACE_FILE"'
run $p $tmp/bin/ensure-nix-zsh-shell $tmp/no-such-zsh
assert_eq $rc 0
assert_contains "$out" 'nothing to do'
: >$tmp/fake-zsh
chmod +x $tmp/fake-zsh
: >$tmp/trace
run $p $tmp/bin/ensure-nix-zsh-shell $tmp/fake-zsh
assert_eq $rc 0
assert_contains "$out" 'login shell left unchanged (non-interactive; no sudo)'
assert_not_contains "$(cat -- $tmp/trace)" 'usermod'

# --- mdp-status: readiness from container state and HTTP/TCP probes ---
install_helper mdp-status
p=$(stubdir status)
stub $p docker 'case "$3" in *Health*) [ "$FIX_DOCKER" = up ] && echo healthy || echo unhealthy ;; *) [ "$FIX_DOCKER" = up ] && echo true || echo false ;; esac'
stub $p curl '[ "$FIX_DOCKER" = up ] && printf 200 || printf 000'
FIX_DOCKER=up run $p $tmp/bin/mdp-status
assert_eq $rc 0
assert_contains "$out" '  ✓ db container healthy'
assert_contains "$out" 'stack READY'
FIX_DOCKER=down run $p $tmp/bin/mdp-status
assert_eq $rc 1
assert_contains "$out" '  ✗ db container not healthy'
assert_contains "$out" 'stack NOT ready'
FIX_DOCKER=down run $p $tmp/bin/mdp-status --wait --timeout 0
assert_eq $rc 1
assert_contains "$out" 'stack NOT ready after 0s'
run $p $tmp/bin/mdp-status --help
assert_contains "$out" 'mdp-status --wait'
# The SAM TCP probe, on a free port (MDP_STATUS_SAM_PORT) so both states are seen
# whatever is listening on the real :3000.
zmodload zsh/net/tcp
sam_port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
MDP_STATUS_SAM_PORT=$sam_port FIX_DOCKER=up run $p $tmp/bin/mdp-status
assert_contains "$out" "SAM local API not listening (:$sam_port)"
python3 -c 'import socket, sys, time; s=socket.socket(); s.bind(("127.0.0.1", int(sys.argv[1]))); s.listen(); time.sleep(15)' $sam_port &
listener=$!
for i in {1..50}; do
	ztcp 127.0.0.1 $sam_port 2>/dev/null && {
		ztcp -c $REPLY
		break
	}
	sleep 0.1
done
MDP_STATUS_SAM_PORT=$sam_port FIX_DOCKER=up run $p $tmp/bin/mdp-status
kill $listener 2>/dev/null || true
assert_contains "$out" "SAM local API listening (:$sam_port)"

# --- setup-gdrive-remote: every path short of the browser OAuth ---
install_helper setup-gdrive-remote
mkdir -p $tmp/repo/secrets $tmp/cfg/sops/age $tmp/home/.local/bin
print -r -- '{}' >$tmp/repo/secrets/rclone-gdrive.json
print -r -- 'AGE-SECRET-KEY-1FIXTURE' >$tmp/cfg/sops/age/keys.txt
stub $tmp/home/.local/bin sync-to-gdrive 'printf "sync-to-gdrive %s\n" "$*"'
p=$(stubdir gdrive)
stub $p rclone 'printf "rclone %s\n" "$*" >>"$TRACE_FILE"; [ "$1" = listremotes ] && printf "%b" "${FIX_REMOTES:-}"; exit 0'
stub $p sops 'printf "%s\n" "$FIX_JSON"'
ln -sf $(command -v jq) $p/
gdrive() { NIX_CONFIG_DIR=$tmp/repo XDG_CONFIG_HOME=$tmp/cfg HOME=$tmp/home FIX_REMOTES=${FIX_REMOTES-} FIX_JSON=${FIX_JSON-} run "$@"; }
p_norclone=$(stubdir norclone)
ln -sf $p/sops $p/jq $p_norclone/
gdrive $p_norclone $tmp/bin/setup-gdrive-remote
assert_eq $rc 1
assert_contains "$out" 'rclone is not installed'
NIX_CONFIG_DIR=$tmp/empty-repo XDG_CONFIG_HOME=$tmp/cfg HOME=$tmp/home run $p $tmp/bin/setup-gdrive-remote
assert_eq $rc 1
assert_contains "$out" 'missing'
NIX_CONFIG_DIR=$tmp/repo XDG_CONFIG_HOME=$tmp/no-cfg HOME=$tmp/home run $p $tmp/bin/setup-gdrive-remote
assert_eq $rc 1
assert_contains "$out" 'no age key'
: >$tmp/trace
FIX_REMOTES='gdrive:\n' gdrive $p $tmp/bin/setup-gdrive-remote
assert_eq $rc 0
assert_file_contains $tmp/trace 'rclone config reconnect gdrive:'
assert_contains "$out" 'sync-to-gdrive --dry-run'
: >$tmp/trace
FIX_JSON='{"installed":{"client_id":"cid-1","client_secret":"csec-1"}}' gdrive $p $tmp/bin/setup-gdrive-remote
assert_eq $rc 0
assert_file_contains $tmp/trace 'rclone config create gdrive drive scope=drive client_id=cid-1 client_secret=csec-1'
FIX_JSON='{"installed":{"client_id":null}}' gdrive $p $tmp/bin/setup-gdrive-remote
assert_eq $rc 1
assert_contains "$out" 'could not read client credentials'

# --- update-agent-clis (as Linux): update in place, or bootstrap via installer ---
install_helper update-agent-clis
p=$(stubdir agents)
stub $p uname 'echo Linux'
stub $p curl 'case "$*" in *claude*) echo "echo claude-installer-ran" ;; *copilot*) echo "echo copilot-installer-ran" ;; esac'
mkdir -p $tmp/agents-home/.local/bin
for cli in claude copilot; do
	stub $tmp/agents-home/.local/bin $cli "[ \"\$1\" = update ] && printf '$cli update\n' >>\"\$TRACE_FILE\"; [ \"\$1\" = --version ] && echo '$cli 9.9'; exit 0"
done
: >$tmp/trace
HOME=$tmp/agents-home run $p $tmp/bin/update-agent-clis
assert_eq $rc 0
assert_file_contains $tmp/trace 'claude update'
assert_file_contains $tmp/trace 'copilot update'
assert_contains "$out" '==> claude   claude 9.9'
assert_not_contains "$out" 'codex'
HOME=$tmp/agents-empty run $p $tmp/bin/update-agent-clis
assert_eq $rc 0
assert_contains "$out" 'claude-installer-ran'
assert_contains "$out" 'copilot-installer-ran'
assert_contains "$out" '(not runnable)'
p_nocurl=$(stubdir nocurl)
ln -sf $p/uname $p_nocurl/
HOME=$tmp/agents-home run $p_nocurl $tmp/bin/update-agent-clis
assert_eq $rc 0
assert_contains "$out" 'curl not found'
print -r -- 'small-helpers: ok'
