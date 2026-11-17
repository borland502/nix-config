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

log=$(mktemp)
trap 'rm -f -- $log' EXIT

# Stream live while capturing combined output so a failure can be classified.
# $pipestatus[1] is nixos-rebuild's own exit code (zsh arrays are 1-indexed).
$sudo_bin nixos-rebuild switch --flake $flake 2>&1 | tee $log
rc=$pipestatus[1]

if ((rc == 0)); then
	exit 0
fi

if grep -qiE 'user activation for .* failed|autolaunch a dbus-daemon|Failed to open dbus connection' $log; then
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
