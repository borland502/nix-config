#!/usr/bin/env bash
# Apply chezmoi dotfiles with a heartbeat and a timeout backstop.
#
# chezmoi apply is silent while it fetches externals, and an impatient Ctrl-C
# mid-apply wedges the chezmoi state lock — so this prints a dotted heartbeat
# to show it is alive. --keep-going means a failing external
# (unreachable/private/rate-limited/deleted repo) is reported but does not
# abort the rest of the apply; on a genuine timeout it retries once without
# externals so the dotfiles still land.
set -euo pipefail

chezmoi_cmd="${1:?usage: chezmoi-apply-tolerant.sh <chezmoi-cmd> <source-dir>}"
src="${2:?usage: chezmoi-apply-tolerant.sh <chezmoi-cmd> <source-dir>}"

# Persist the apply output. Previously it streamed straight to the terminal, so
# a failure left no record but scrollback — and the message below asserted an
# external was to blame without ever checking. Reconstructing which one meant
# re-running the whole refresh by hand. cache-scan indexes this directory, and
# compress-old-cache zstd-compresses it after a day.
log_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude"
mkdir -p "$log_dir"
log="$log_dir/chezmoi-apply-$(date +%Y%m%d-%H%M%S).log"

# shellcheck disable=SC2086
eval $chezmoi_cmd init --source "$src"

echo "==> applying chezmoi dotfiles (refreshing any due externals — do not cancel)"
echo "    log: $log"
(
	while true; do
		sleep 8
		printf '    …still applying dotfiles (do not cancel)\n'
	done
) &
hb=$!
trap 'kill "$hb" 2>/dev/null || true' EXIT

# Take the exit code from the pipeline's FIRST element. The previous form —
# `if ! timeout …; then rc=$?` — always set rc=0, because inside the branch $? is
# the status of the negation, not of the command. So the message below reported
# "rc=0" on every failure and the rc=124 timeout branch was unreachable.
set +e
# shellcheck disable=SC2086
timeout -k 10 300 bash -c "$chezmoi_cmd apply --force --keep-going" 2>&1 | tee "$log"
rc="${PIPESTATUS[0]}"
set -e

kill "$hb" 2>/dev/null || true

if [[ "$rc" -ne 0 ]]; then
	echo "chezmoi apply failed (rc=$rc) — continuing with the switch." >&2
	echo "  full output: $log" >&2
	# Only blame an external when chezmoi actually named one. grep rather than rg
	# because this runs on the bootstrap path, before the nix profile is
	# guaranteed to exist.
	if grep -qE '\.local/src|external' "$log"; then
		echo "  external-related lines (likely cause):" >&2
		grep -nE '\.local/src|external' "$log" | tail -5 | sed 's/^/    /' >&2 || true
	else
		echo "  No external is named in the output — the failure is something else:" >&2
		grep -niE 'error|failed|cannot|unable|denied|permission' "$log" |
			tail -5 | sed 's/^/    /' >&2 || true
	fi
	if [[ "$rc" -eq 124 ]]; then
		echo "chezmoi timed out; re-applying without externals so dotfiles still land." >&2
		# shellcheck disable=SC2086
		eval $chezmoi_cmd apply --force --keep-going --exclude=externals || true
	fi
fi
