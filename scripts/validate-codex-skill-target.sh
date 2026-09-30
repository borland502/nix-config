#!/usr/bin/env bash
# Return success when an existing Codex skill target is demonstrably managed by
# this nix-config generation or one of its recognized legacy layouts.
set -euo pipefail

if [[ $# -ne 4 ]]; then
	printf 'usage: validate-codex-skill-target SOURCE TARGET NAME MANIFEST\n' >&2
	exit 64
fi

source_dir="$1"
target="$2"
name="$3"
manifest="$4"
marker=.nix-config-managed

[[ -d "$source_dir" ]] || exit 1
case "$name" in
"" | . | .. | */*) exit 1 ;;
esac

if [[ -f "$target/$marker" ]]; then
	exit 0
fi

# The manifest is the ownership ledger written by the previous generation.
# Managed content is expected to differ when a skill is upgraded.
if [[ -f "$manifest" ]] && grep -Fxq -- "$name" "$manifest"; then
	exit 0
fi

if [[ -L "$target" ]]; then
	resolved_target="$(readlink -f "$target")"
	case "$resolved_target" in
	/nix/store/*-hm_*) exit 0 ;;
	esac
fi

if [[ -L "$target/SKILL.md" ]]; then
	resolved_leaf="$(readlink -f "$target/SKILL.md")"
	case "$resolved_leaf" in
	/nix/store/*-hm_skills/"$name"/SKILL.md) exit 0 ;;
	esac
fi

# Compatibility for short-lived materialized copies that predate the manifest.
# Only exact content matches are adopted through this fallback.
if [[ -d "$target" ]]; then
	compare_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-skill-compare.XXXXXX")"
	trap 'rm -rf "$compare_dir"' EXIT
	cp -RLp "$source_dir/." "$compare_dir/"
	chmod -R u+w "$compare_dir"
	if diff -qr "$compare_dir" "$target" >/dev/null; then
		exit 0
	fi
fi

exit 1
