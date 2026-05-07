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
* `task`

Skip any tool where its `--help` is so simple that a skill page adds no
information beyond "see `--help`".

## Skill Prefix Categorization

Group the 43 skills under `ai-tools/skills/` by domain prefix so the
`/<command>` name self-documents its bucket. Claude Code does not support
nested skill subdirectories, so prefixes are the closest thing to
folders. Approach: keep + rename upstream-derived skills (so they remain
locally modifiable and can absorb future merges from multiple sources)
rather than introducing a flatten-on-deploy build step.

**Prefix scheme:**

* `cli-` — CLI tool wrappers (`rg`, `fd`, `jq`, `yq`, `sd`, `dasel`, `fzf`)
* `git-` — SCM / PR workflow
* `flow-` — development methodology (mostly obra/superpowers-derived)
* `web-` — browser / scraping
* `sec-` — security
* `ops-` — infra / system
* (no prefix) — language-prefixed skills already self-group:
  `angular-*`, `bun-runtime`, `golang-*`, `python-*`, `springboot-*`

**Renames (30 of 43):**

| Current | New |
|---|---|
| `dasel` | `cli-dasel` |
| `fd` | `cli-fd` |
| `fzf` | `cli-fzf` |
| `jq` | `cli-jq` |
| `rg` | `cli-rg` |
| `sd` | `cli-sd` |
| `yq` | `cli-yq` |
| `using-git-worktrees` | `git-worktrees` |
| `finishing-a-development-branch` | `git-finish-branch` |
| `requesting-code-review` | `git-request-review` |
| `executing-plans` | `flow-executing-plans` |
| `writing-plans` | `flow-writing-plans` |
| `writing-skills` | `flow-writing-skills` |
| `systematic-debugging` | `flow-systematic-debugging` |
| `test-driven-development` | `flow-test-driven-development` |
| `subagent-driven-development` | `flow-subagent-driven-development` |
| `verification-before-completion` | `flow-verification-before-completion` |
| `reconciliation` | `flow-reconciliation` |
| `chrome-devtools-cli` | `web-chrome-devtools-cli` |
| `nodriver-browser` | `web-nodriver-browser` |
| `playwright-cli` | `web-playwright-cli` |
| `html-to-markdown` | `web-html-to-markdown` |
| `security-review` | `sec-review` |
| `security-scan` | `sec-scan` |
| `sops-encrypt` | `sec-sops-encrypt` |
| `chezmoi` | `ops-chezmoi` |
| `nix-pitfalls` | `ops-nix-pitfalls` |
| `cache-scan` | `ops-cache-scan` |
| `repo-scan` | `ops-repo-scan` |
| `jira-integration` | `ops-jira-integration` |

**Left unchanged (13):** `angular-developer`, `angular-new-app`,
`bun-runtime`, `golang-patterns`, `golang-testing`, `python-patterns`,
`python-testing`, `springboot-patterns`, `springboot-security`,
`springboot-tdd`, `springboot-verification`, `git-workflow`,
`github-ops`, `ops-agent`.

**Per-rename mechanics:**

1. `git mv ai-tools/skills/<old> ai-tools/skills/<new>`
2. Update `name:` in the skill's `SKILL.md` frontmatter to match.
3. Search-and-replace cross-references:
   * `nix-config-tools:<old>` → `nix-config-tools:<new>` in other
     SKILL.md bodies (heaviest in the `flow-` cluster)
   * Relative path links: `../<old>/SKILL.md` → `../<new>/SKILL.md`
   * `README.md` lines 280-287 (upstream-source table)
   * `writing-skills/render-graphs.js` example comment
   * `subagent-driven-development/code-quality-reviewer-prompt.md`
     reference to `requesting-code-review/code-reviewer.md`
4. Verify with `home-manager switch` that symlinks still resolve under
   `~/.config/claude/skills/` and `~/.config/copilot/skills/`.

**Do NOT rewrite:** binary names that happen to match a skill slug
(`playwright-cli`, `cache-scan`, `html-to-markdown`, etc.) — those are
real commands documented by the skill, not skill references. Only the
directory name and `name:` frontmatter change.

**PR strategy — one PR per prefix, in this order (smallest blast radius
first):**

1. `web-` (4 renames, mostly self-contained)
2. `sec-` (3 renames, few cross-refs)
3. `ops-` (5 renames, some `chezmoi`/`sops-encrypt` cross-refs to fix)
4. `cli-` (7 renames, low cross-skill coupling)
5. `git-` (3 renames, referenced by the flow cluster)
6. `flow-` (8 renames, dense internal cross-references — do last so all
   targets already exist)

keep the local copies and treat the prefixed names as the canonical local fork.

## Buried Behaviors → Surface As Skills

Run after the prefix-rename work lands (so new skills land already
prefixed under the right bucket). These are AI-assistant behaviors
currently encoded only in CLAUDE.md, hooks, or one-off scripts — a
fresh session has no skill to discover them.

**New skills (2):**

* **`sec-credentials`** — codifies the CLAUDE.md rule "check `~/.cache`
  then `~/.config` for tool credentials" and the sops → legacy-path
  fallback pattern implemented in
  [home-manager/local/bin/ops-agent.py](home-manager/local/bin/ops-agent.py).
  Triggers on "where's the token / auth / credential for X" type
  questions. Should reference `sec-sops-encrypt` for the encryption
  side and `ops-agent` for the canonical fallback example.

* **`shell-pitfalls`** — consolidates shell anti-patterns currently
  scattered across instruction files: aliases hide real binaries (use
  `/bin/ls`, `/bin/cat` when exact output is needed); zsh `status` is
  read-only (use `rc` or `exit_code`); the heavy-quoting heuristic
  from [agent-defaults.md:27](chezmoi/dot_config/instructions/agent-defaults.md#L27)
  ("when a command with JSON payloads or heavy quoting fails, write a
  short script file under `~/.cache/<agent>/` and execute that
  instead of retrying inline `zsh -c`"); the wrapped-capture
  permission-denied retry trick from
  [agent-defaults.md:25](chezmoi/dot_config/instructions/agent-defaults.md#L25).
  Could alternatively be folded into `ops-nix-pitfalls` if we don't
  want a separate skill.

**Skill updates (3):**

* **`jira-integration` → make REST-first explicit.** CLAUDE.md says
  prefer direct REST/API requests over `jira-cli`/`confluence-cli`
  wrappers. Today this is a one-liner in CLAUDE.md and the skill
  doesn't enforce it. Promote REST as the loud default; demote CLI
  wrappers to a "fallback when no token is available" footnote.

* **`ops-cache-scan` (post-rename) → document the log source.** The
  `PostToolUse` hook in
  [home-manager/common.nix:228-239](home-manager/common.nix#L228-L239)
  pipes every Bash command + output to `~/.cache/<agent>/*.log` via
  [home-manager/local/bin/log-bash.sh](home-manager/local/bin/log-bash.sh).
  Add a one-paragraph pointer in the SKILL.md so future sessions know
  why those logs exist and that the hook is automatic (not something
  to wire up themselves).

* **`flow-systematic-debugging` (post-rename) → add a Phase 0 "check
  the log first."** Codifies the procedure from
  [agent-defaults.md:10](chezmoi/dot_config/instructions/agent-defaults.md#L10):
  before retrying a failed command, grep `~/.cache/<agent>/*.log` for
  prior successful invocations of the same tool and use them as
  concrete templates. Pairs naturally with the `ops-cache-scan`
  update — that skill produces the index, this one consumes it.

* **`ops-nix-pitfalls` (post-rename) → optional sink for shell
  pitfalls.** If we don't create a standalone `shell-pitfalls` skill,
  fold the alias-escaping / zsh-`status` content here.

**Explicitly NOT skills:**

* The `log-bash.sh` PostToolUse hook itself — it's plumbing, fires
  automatically, no decision surface for an LLM to invoke. Just needs
  to be *discoverable* via the `ops-cache-scan` update above.
* Marketplace registration in
  [home-manager/common.nix:260-315](home-manager/common.nix#L260-L315) —
  pure setup automation, runs at activation time.
* Agent-specific cache paths (`@@AGENT@@` placeholder substitution) —
  build-time concern, not session-time behavior.

