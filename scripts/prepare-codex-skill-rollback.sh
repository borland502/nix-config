#!/usr/bin/env -S zsh -f
# Before `task darwin-rollback`: undo an interrupted Codex skill migration, and
# drop Home Manager skill links the older recursive layout would collide with.
# Covered by tests/test_codex_skill_ownership.zsh.
emulate -R zsh
setopt err_exit no_unset pipe_fail

skills_root=${XDG_CONFIG_HOME:-$HOME/.config}/codex/skills
[[ -d $skills_root ]] || exit 0
repo_root=${0:A:h:h}

# (N): no match is an empty loop, not an error (bash's nullglob).
for target in $skills_root/*(N); do
	[[ -L $target ]] || continue
	name=${target:t}
	backup=$skills_root/.nix-config-skill-backup-$name
	raw_target=$(readlink $target)

	if [[ $raw_target == $backup && -d $backup ]]; then
		rm $target
		mv $backup $target
		printf 'restored interrupted Codex skill migration: %s\n' $name
		continue
	fi

	resolved_target=$(readlink -f $target 2>/dev/null || true)
	case $resolved_target in
	/nix/store/*-hm_*)
		source_dir=$repo_root/ai-tools/skills/$name
		[[ -d $source_dir ]] || continue
		diff -qr $source_dir $target >/dev/null || continue
		if [[ -e $backup || -L $backup ]]; then
			printf 'refusing rollback with unresolved Codex skill backup: %s\n' $name >&2
			exit 1
		fi
		rm $target
		printf 'prepared Codex skill for recursive-layout rollback: %s\n' $name
		;;
	esac
done
