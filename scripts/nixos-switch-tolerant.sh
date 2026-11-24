#!/usr/bin/env -S zsh -f
# Run `nixos-rebuild switch` for the given flake, tolerating the benign
# post-activation failure to reload a user's systemd session over D-Bus.
#
# On headless NixOS-WSL there is no session bus / $DISPLAY, so reloading user
# units fails and switch-to-configuration exits non-zero (status 4) even though
# the system and home configuration both activated. The first switch that
# changes wsl.defaultUser additionally removes the bootstrap user (e.g. the
# tarball's `nixos`), which trips the same reload failure for the departing
# user. We detect that signature and downgrade it to a warning; every other
# failure is propagated unchanged.
#
# SWITCH_SUDO overrides the sudo binary; tests/test_switch_tolerant.zsh uses it
# so a NixOS test host never runs the real /run/wrappers sudo.
emulate -R zsh
# No err_exit: a failing rebuild is classified below rather than ending the script.
setopt no_unset pipe_fail

flake=${1:?usage: nixos-switch-tolerant.sh <flake-ref>}

# nix-command/flakes are disabled by default on a fresh NixOS-WSL.
export NIX_CONFIG="experimental-features = nix-command flakes${NIX_CONFIG:+
$NIX_CONFIG}"

if [[ -n ${SWITCH_SUDO-} ]]; then
	sudo_bin=$SWITCH_SUDO
elif [[ -x /run/wrappers/bin/sudo ]]; then
	sudo_bin=/run/wrappers/bin/sudo
else
	sudo_bin=sudo
fi

log_dir=${XDG_CACHE_HOME:-$HOME/.cache}/claude
mkdir -p -- $log_dir
log=$(mktemp $log_dir/nixos-switch-XXXXXXXX)
print -ru2 -- "nixos-rebuild log: $log"

# Stream live while capturing combined output so a failure can be classified.
# $pipestatus[1] is nixos-rebuild's own exit code (zsh arrays are 1-indexed).
$sudo_bin nixos-rebuild switch --flake $flake 2>&1 | tee $log
rc=$pipestatus[1]

if ((rc == 0)); then
	exit 0
fi

# A D-Bus error only explains the user reload containing it. Never let one
# user's expected failure hide another user's failure or a system-bus error.
only_user_dbus_failures() {
	local line normalized active_user='' MATCH
	local -a match
	local -i active_dbus=0 active_context=0 saw_failure=0
	local user_start='^reloading user units for ([[:alnum:]_.-]+)\.\.\.$'
	local user_failure='^(warning: )?user activation for ([[:alnum:]_.-]+) failed$'
	local dbus_failure='^(failed to open dbus connection(: (no such file or directory|connection refused))?|cannot autolaunch d-bus without x11 \$display)$'
	local rust_cause='^[[:space:]]+(no such file or directory|connection refused|cannot autolaunch d-bus without x11 \$display)$'
	local bus_detail='^failed to connect to bus: (no such file or directory|connection refused)$'
	while IFS= read -r line || [[ -n $line ]]; do
		normalized=${(L)line}
		if [[ $normalized =~ $user_start ]]; then
			((active_dbus || active_context)) && return 1
			active_user=$match[1]
		elif [[ $normalized =~ $user_failure ]]; then
			[[ -n $active_user && $active_user == $match[2] ]] && ((active_dbus)) || return 1
			saw_failure=1
			active_user=''
			active_dbus=0
			active_context=0
		elif [[ $normalized == 'error: failed to open dbus connection' ]]; then
			[[ -n $active_user ]] || return 1
			active_context=1
		elif [[ $normalized =~ $rust_cause ]]; then
			((active_context)) || return 1
			active_dbus=1
		elif [[ $normalized =~ $dbus_failure ]]; then
			[[ -n $active_user ]] || return 1
			active_dbus=1
		elif [[ $normalized =~ $bus_detail ]]; then
			[[ -n $active_user ]] && ((active_dbus)) || return 1
		elif [[ $normalized =~ 'error|fail|denied|unable|cannot' ]]; then
			return 1
		fi
	done <"$1"
	((saw_failure && !active_dbus && !active_context))
}

if ((rc == 4)) && only_user_dbus_failures "$log"; then
	cat >&2 <<EOF

WARNING: nixos-rebuild returned $rc, but the only activation failure was reloading
         a user's systemd session over D-Bus. This is expected on headless
         NixOS-WSL (no session bus / \$DISPLAY) and on the first switch that
         changes wsl.defaultUser (the outgoing bootstrap user is removed). The
         system and home configuration activated successfully.
         Run 'wsl --shutdown' and start a new session to finish applying changes.
EOF
	exit 0
fi

print -ru2 -- "nixos-rebuild failed (exit $rc) for reasons other than the D-Bus user reload — see output above."
exit $rc
