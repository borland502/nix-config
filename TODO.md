# TODO

## Fix errors

```console
Please do one of the following:
- In standalone mode, use 'home-manager switch -b backup' to back up files automatically.
- When used as a NixOS or nix-darwin module, set either
  - 'home-manager.backupFileExtension', or
  - 'home-manager.backupCommand',
  to move the file to a new location in the same directory, or run a custom command.
- Set 'force = true' on the related file options to forcefully overwrite the files below. eg. 'xdg.configFile."mimeapps.list".force = true'
Existing file '/home/jhettenh/.config/claude/CLAUDE.md' would be clobbered
task: Failed to run task "upgrade": exit status 1
direnv: loading ~/.config/nix-config/.envrc
direnv: using flake
```

## Tool Skill Additions

The Phase 4c/4d batch covered `jq`, `dasel`, `rg`, `fd`, `yq`, `sd`,
`fzf`.  The remaining shared-tooling-list candidates with non-trivial
complexity, deferred for later if/when needed:

* `bat`   — cat with syntax highlighting + paging
* `eza`   — ls replacement (already aliased to `ls` in zsh, so triggers
            are ambient — lower-priority skill)
* `tmux`  — terminal multiplexer
* `gum`   — interactive shell prompts (sibling of fzf)
* `direnv` — per-dir env loading (mostly auto-magic; skill mainly useful
            for debugging `.envrc` failures)
* `gh`    — already covered indirectly by the ingested `github-ops` skill;
            a dedicated `gh` page would overlap

Skip any tool where its `--help` is so simple that a skill page adds no
information beyond "see `--help`".
