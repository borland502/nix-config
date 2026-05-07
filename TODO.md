# TODO

## Fix errors

## Tool Skill Additions

* `bat`   — cat with syntax highlighting + paging
* `eza`   — ls replacement (already aliased to `ls` in zsh, so triggers
            are ambient — lower-priority skill)
* `tmux`  — terminal multiplexer
* `gum`   — interactive shell prompts (sibling of fzf)
* `direnv` — per-dir env loading (mostly auto-magic; skill mainly useful
            for debugging `.envrc` failures)
* `gh`    — already covered indirectly by the ingested `github-ops` skill;
            a dedicated `gh` page would overlap
* `task`

Skip any tool where its `--help` is so simple that a skill page adds no
information beyond "see `--help`".

## Tool Ingestion

* [javascript-typescript](https://github.com/wshobson/agents/tree/main/plugins/javascript-typescript)
  * Convert the claude specific plugin format to fit this project
* [obsidian-skills](https://github.com/kepano/obsidian-skills)
* [awesome-copilot](https://github.com/github/awesome-copilot/tree/main)
  * Extract skills for git, github, and react
* [agent-toolkit-for-aws](https://github.com/aws/agent-toolkit-for-aws)
