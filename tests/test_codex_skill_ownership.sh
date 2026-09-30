#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
validator="$repo_root/scripts/validate-codex-skill-target.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/source" "$tmp/target"
printf 'new generation\n' >"$tmp/source/SKILL.md"
printf 'old generation\n' >"$tmp/target/SKILL.md"

# A manifest is the ownership ledger. Managed content may legitimately differ
# from the new generation during an upgrade.
printf 'git-worktrees\n' >"$tmp/manifest"
"$validator" "$tmp/source" "$tmp/target" git-worktrees "$tmp/manifest"

# Marker-owned materialized copies are also safe to replace.
: >"$tmp/empty-manifest"
: >"$tmp/target/.nix-config-managed"
"$validator" "$tmp/source" "$tmp/target" git-worktrees "$tmp/empty-manifest"
rm "$tmp/target/.nix-config-managed"

# An unclaimed but byte-identical legacy copy remains migratable.
cp "$tmp/source/SKILL.md" "$tmp/target/SKILL.md"
"$validator" "$tmp/source" "$tmp/target" git-worktrees "$tmp/empty-manifest"

# A genuinely unowned, differing directory must still fail closed.
printf 'independent installation\n' >"$tmp/target/SKILL.md"
if "$validator" "$tmp/source" "$tmp/target" git-worktrees "$tmp/empty-manifest"; then
	printf 'unowned differing skill was incorrectly accepted\n' >&2
	exit 1
fi
