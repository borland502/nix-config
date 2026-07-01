#!/usr/bin/env bash
# Run `darwin-rebuild switch` for the given flake, tolerating two benign
# conditions that otherwise fail `task switch` / `task upgrade`:
#
#   1. Home Manager's cosmetic orphan-link spam (~530 lines/run) left by the
#      stale *.instructions.md -> *.prompt.md prompt-bridge migration; the
#      referenced files are already gone. Filtered from the live stream.
#
#   2. Homebrew cask DOWNLOAD failures. Work VPNs frequently reset the
#      connection to certain vendor URLs (Discord, WhatsApp, ...), so
#      `brew bundle` exits non-zero even though the nix system generation and
#      every reachable cask activated. We downgrade *that specific* failure to a
#      warning. Any other failure — a nix build/eval error, or a non-download
#      Homebrew error — is propagated unchanged.
set -uo pipefail

orphan='does not link into a Home Manager generation\. Skipping delete\.'

# classify_log <logfile> -> exit 0 when the only failure was blocked Homebrew
# cask downloads (tolerable); non-zero when a real failure is present.
classify_log() {
	local log="$1"
	# Require a positive cask-download signal before tolerating anything.
	grep -qE 'Download failed on Cask' "$log" || return 1
	# nix build/eval failures use a lowercase `error:` (case-sensitive, so the
	# Homebrew `Error: Download failed` lines below do not trip this).
	if grep -qE '^error:|builder for .* failed|build of .* failed|hash mismatch|infinite recursion|cannot coerce' "$log"; then
		return 1
	fi
	# A Homebrew `Error:` that is not a download failure (checksum, conflicting
	# install, ...) is a real failure too.
	if grep -E '^Error:' "$log" | grep -qvE 'Download failed'; then
		return 1
	fi
	return 0
}

# Diagnostic/test hook: classify an existing log without running a rebuild.
if [[ "${1:-}" == "--classify" ]]; then
	classify_log "${2:?usage: darwin-switch-tolerant.sh --classify <logfile>}"
	rc=$?
	[[ "$rc" -eq 0 ]] && echo "tolerate" || echo "propagate"
	exit "$rc"
fi

flake="${1:?usage: darwin-switch-tolerant.sh <flake-ref>}"

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

# Stream live (minus the orphan spam) while capturing the full combined output
# so a non-zero exit can be classified. PIPESTATUS[0] keeps darwin-rebuild's own
# exit code rather than tee's or grep's.
set -o pipefail
sudo darwin-rebuild switch --flake "$flake" 2>&1 |
	tee "$log" |
	grep --line-buffered -v "$orphan"
rc="${PIPESTATUS[0]}"

if [[ "$rc" -eq 0 ]]; then
	exit 0
fi

if classify_log "$log"; then
	cat >&2 <<'EOF'

WARNING: darwin-rebuild returned non-zero, but the only failure was Homebrew
         cask DOWNLOADS being blocked (common on a work VPN that resets certain
         vendor URLs). The nix system generation and every reachable cask
         activated successfully. Re-run `task switch` off-VPN to fetch the
         blocked casks.
EOF
	exit 0
fi

echo "darwin-rebuild failed (exit $rc) for reasons beyond blocked Homebrew cask downloads — see output above." >&2
exit "$rc"
