# TODO

Items addressed by the `feat/ai-tools-ingestion` branch (Phases 0–4) have
been removed.  What remains is genuinely outstanding work.

## Phase 5 — install/deploy integration

* Add any CLI applications introduced by ingested skills (e.g. browser
  automation: playwright, nodriver/Chromium runtime; Python deps for
  agentic-search) to the shared tooling defaults in
  `chezmoi/dot_config/instructions/agent-defaults.md` so both Copilot
  and Claude know they're available — only for tools that should be
  globally installed via home-manager, not skill-internal venvs.
* Ensure that `task upgrade` runs at the end of `install.sh`.
* End-to-end verify on a clean host: `task switch` deploys the plugin
  and skills into `~/.config/{claude,copilot}/{skills,agents}/` and
  registers both marketplaces (`nix-config-dev` + `anthropic-agent-skills`)
  in `~/.config/claude/settings.json`.

## Phase 6 — README + final pass

* Credit all upstream skill repositories in `README.md` (anthropic/skills,
  obra/superpowers, affaan-m/everything-claude-code, appautomaton/webmaton,
  angular/skills) with their licenses noted.
* Final lint/build/test pass.

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
