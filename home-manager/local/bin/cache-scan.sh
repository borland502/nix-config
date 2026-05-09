#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: cache-scan [--date YYYY-MM-DD] [--days N]

Scans ~/.cache/copilot and ~/.cache/claude for recent log activity,
common failure patterns, and resumable context clues.
EOF
}

date_filter="$(date +%F)"
days=1

while [[ $# -gt 0 ]]; do
	case "$1" in
	--date)
		shift
		date_filter="${1:-}"
		[[ -n "$date_filter" ]] || {
			usage
			exit 1
		}
		;;
	--days)
		shift
		days="${1:-}"
		[[ "$days" =~ ^[0-9]+$ ]] || {
			echo "--days must be a number" >&2
			exit 1
		}
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "Unknown argument: $1" >&2
		usage
		exit 1
		;;
	esac
	shift
done

roots=("$HOME/.cache/copilot" "$HOME/.cache/claude")

find_existing_roots() {
	for root in "${roots[@]}"; do
		[[ -d "$root" ]] && echo "$root"
	done
}

mapfile -t existing_roots < <(find_existing_roots)
if [[ ${#existing_roots[@]} -eq 0 ]]; then
	echo "No cache roots found under ~/.cache/copilot or ~/.cache/claude"
	exit 0
fi

echo "== Cache Scan =="
echo "Date filter: $date_filter"
echo "Lookback days: $days"
echo

echo "== Recent Files (Top 20) =="
find "${existing_roots[@]}" -type f -mtime "-$days" \
	\( -name "*.log" -o -name "*.out" -o -name "*.err" -o -name "*.txt" \) \
	-print0 | xargs -0 ls -lt 2>/dev/null | head -20 || true
echo

echo "== Files Matching Date =="
find "${existing_roots[@]}" -type f -mtime "-$days" \
	\( -name "*${date_filter}*" -o -name "*.log" -o -name "*.out" \) |
	sort | tail -40
echo

echo "== Failure Pattern Counts =="
rg -i --no-heading --stats \
	"error|failed|traceback|permission denied|exit code|exception|fatal" \
	"${existing_roots[@]}" 2>/dev/null | tail -20 || true
echo

echo "== Failure Pattern Breakdown =="
for pattern in "error" "failed" "traceback" "permission denied" "exit code" "exception" "fatal"; do
	count=$(rg -i --count-matches "$pattern" "${existing_roots[@]}" 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')
	printf "%-18s %s\n" "$pattern" "$count"
done
echo

echo "== Candidate Resume Points (Last 5 Matching Lines) =="
rg -i -n "task switch|nix run|home-manager|darwin-rebuild|ops-agent|jira|copilot|claude|exit code|failed" \
	"${existing_roots[@]}" 2>/dev/null | tail -5 || true
