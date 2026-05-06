# TODO

The `feat/ai-tools-ingestion` branch (Phases 0–6) is complete.  This file
holds only deferred / future-considerations work.

## Future — additional CLI tool skill pages

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
