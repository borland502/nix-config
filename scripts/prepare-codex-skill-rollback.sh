#!/usr/bin/env bash
set -euo pipefail

skills_root="${XDG_CONFIG_HOME:-$HOME/.config}/codex/skills"
[[ -d "$skills_root" ]] || exit 0
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

shopt -s nullglob
for target in "$skills_root"/*; do
	[[ -L "$target" ]] || continue
	name="${target##*/}"
	backup="$skills_root/.nix-config-skill-backup-$name"
	raw_target=$(readlink "$target")

	if [[ "$raw_target" == "$backup" && -d "$backup" ]]; then
		rm "$target"
		mv "$backup" "$target"
		printf 'restored interrupted Codex skill migration: %s\n' "$name"
		continue
	fi

	resolved_target=$(readlink -f "$target" 2>/dev/null || true)
	case "$resolved_target" in
	/nix/store/*-hm_*)
		source_dir="$repo_root/ai-tools/skills/$name"
		[[ -d "$source_dir" ]] || continue
		diff -qr "$source_dir" "$target" >/dev/null || continue
		if [[ -e "$backup" || -L "$backup" ]]; then
			printf 'refusing rollback with unresolved Codex skill backup: %s\n' "$name" >&2
			exit 1
		fi
		rm "$target"
		printf 'prepared Codex skill for recursive-layout rollback: %s\n' "$name"
		;;
	esac
done
