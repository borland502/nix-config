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

# shellcheck disable=SC2086
eval $chezmoi_cmd init --source "$src"

echo "==> applying chezmoi dotfiles (refreshing any due externals — do not cancel)"
(
  while true; do
    sleep 8
    printf '    …still applying dotfiles (do not cancel)\n'
  done
) &
hb=$!
trap 'kill "$hb" 2>/dev/null || true' EXIT

# shellcheck disable=SC2086
if ! timeout -k 10 300 bash -c "$chezmoi_cmd apply --force --keep-going"; then
  rc=$?
  echo "chezmoi apply reported errors (rc=$rc; one or more externals unavailable) — continuing with the switch."
  if [[ "$rc" -eq 124 ]]; then
    echo "chezmoi timed out; re-applying without externals so dotfiles still land."
    # shellcheck disable=SC2086
    eval $chezmoi_cmd apply --force --keep-going --exclude=externals || true
  fi
fi

kill "$hb" 2>/dev/null || true
