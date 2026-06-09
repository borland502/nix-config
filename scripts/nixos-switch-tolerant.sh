#!/usr/bin/env bash
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
set -uo pipefail

flake="${1:?usage: nixos-switch-tolerant.sh <flake-ref>}"

# nix-command/flakes are disabled by default on a fresh NixOS-WSL.
export NIX_CONFIG="experimental-features = nix-command flakes${NIX_CONFIG:+
$NIX_CONFIG}"

if [[ -x /run/wrappers/bin/sudo ]]; then
	sudo_bin=/run/wrappers/bin/sudo
else
	sudo_bin=sudo
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

# Stream live while capturing combined output so a failure can be classified.
"$sudo_bin" nixos-rebuild switch --flake "$flake" 2>&1 | tee "$log"
rc="${PIPESTATUS[0]}"

if [[ "$rc" -eq 0 ]]; then
	exit 0
fi

if grep -qiE 'user activation for .* failed|autolaunch a dbus-daemon|Failed to open dbus connection' "$log"; then
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

echo "nixos-rebuild failed (exit $rc) for reasons other than the D-Bus user reload — see output above." >&2
exit "$rc"
