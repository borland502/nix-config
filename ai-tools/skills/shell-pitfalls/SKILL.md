---
name: shell-pitfalls
description: Use when a shell command fails with a confusing error, an alias is interfering, a zsh wrapper script has a subtle bug, or a heavily-quoted inline `zsh -c` is failing repeatedly. Consolidates the shell anti-patterns this repo has been bitten by — alias escaping, the zsh `status` read-only trap, when to switch from inline commands to a script file, and the wrapped-capture permission-denied workaround.
---

# Shell Pitfalls

Use this skill when a shell-level issue is the actual blocker — not a logic bug, not a missing file, but the *shell itself* doing something unexpected.

## Aliases hide real binaries

This repo's zsh config aliases `ls` → `eza` and `cat` → `bat` (see [home-manager/zsh.nix](../../../home-manager/zsh.nix)). Both replacements are great for humans but break when a script depends on the exact output format of the original.

**Rule:** when you need exact, unstyled output, bypass the alias by calling the binary directly.

```bash
# Wrong: gets eza's columnar output, breaks downstream parsers
files=$(ls /var/log/*.log)

# Right: real BSD/GNU ls
files=$(/bin/ls /var/log/*.log)

# Wrong: gets bat's syntax highlighting + pager
config=$(cat /etc/hosts)

# Right: raw file contents
config=$(/bin/cat /etc/hosts)
```

The same applies to anything you alias — `command <name>` works as a generic escape hatch (`command ls /tmp`) when you don't want to hardcode `/bin/`.

## zsh `$status` is read-only

In zsh, `status` is a read-only special variable (it mirrors `$?` for the previous pipeline). Assigning to it crashes the script.

```zsh
# Crashes: "status: read-only variable"
status=0
some_command
status=$?

# Use a different name
rc=0
some_command
rc=$?

# Or use $? directly without re-storing
some_command
if [[ $? -ne 0 ]]; then ...; fi
```

**Names to avoid as zsh variables:** `status`, `path`, `cdpath`, `fpath`, `manpath` — these are linked to special arrays/integers. `rc`, `exit_code`, `result` are safe.

Related quoting trap: never emit a bare `==` or `===` as standalone shell text — zsh treats it as a glob/comparison operator and can error or mis-expand. Quote those strings (`"=="`) when they are literal data.

## Heavy quoting → write a script file

When a `zsh -c '...'` fails because of nested quoting, JSON payloads, or escaped-and-re-escaped characters: **stop retrying inline.** Write the command to a file under `~/.cache/<agent>/` and execute the file.

```bash
# Wrong: shell-quoting hell, the second retry will fail differently from the first
zsh -c "curl -X POST https://api.example.com/foo -H 'Content-Type: application/json' -d '{\"key\":\"value with spaces\"}'"

# Right: file-based, no quote escaping
mkdir -p ~/.cache/claude
cat > ~/.cache/claude/post.sh <<'SCRIPT'
#!/usr/bin/env zsh
curl -X POST https://api.example.com/foo \
  -H 'Content-Type: application/json' \
  -d '{"key":"value with spaces"}'
SCRIPT
chmod +x ~/.cache/claude/post.sh
~/.cache/claude/post.sh
```

The file form is also re-runnable (the agent's PostToolUse hook captures the path and contents in the log) and edit-friendly when the API call needs adjusting.

This is the codified version of the heuristic in [chezmoi/dot_config/instructions/agent-defaults.md L27](../../../chezmoi/dot_config/instructions/agent-defaults.md). When you find yourself on the third inline retry, stop and write a script.

For the specific case of `gh api graphql` calls and long/nested `jq` filters — the highest-frequency offender — file-backing is a hard precondition, not a third-retry fallback. See [gh-graphql-jq-pipelines](../gh-graphql-jq-pipelines/SKILL.md) for the sanctioned `.graphql` + `.jq` file shape and the four recurring failure signatures.

## AWS / Kion credential safety

When the local environment uses Kion, load temporary AWS credentials with `source ~/.local/bin/kac ensure` (or read `~/.cache/kion-aws-cache/`) rather than the frequently-stale `~/.aws/credentials` / `AWS_PROFILE`. Treat any value read from a credentials file as a secret — never echo it into command output or a summary.

## `stat`: GNU shadows BSD, even on macOS

On these hosts nix `coreutils` puts **GNU `stat`** on `PATH` ahead of the macOS
BSD `stat` — on darwin and Linux alike. So BSD format syntax silently fails:

```bash
# Wrong on these hosts: GNU stat reads -f as --file-system and treats '%Sm' as a
# filename → "stat: cannot read file system information for '%Sm': No such file…"
stat -f '%Sm' ~/.aws/config

# Right: GNU format syntax
stat -c '%y' ~/.aws/config        # mtime
stat -c '%A %n' ~/.aws/config     # mode + name
```

If you need a portable mtime regardless of which `stat` wins, sidestep it:
`eza -l --time-style=long-iso <file>` or `date -r <file>`. The repo's own
scripts assume GNU `stat -c` for this reason (see `cache-scan`'s header note).

## Wrapped-capture permission-denied retry

Some IDE harnesses wrap shell invocations in a capture command that tightens the executing process's permissions. If a script that *should* be executable returns `permission denied` only when wrapped — but works on a manual run — try invoking it with an explicit `/bin/zsh -f`:

```bash
# Fails inside wrapped capture: "permission denied"
~/.local/bin/some-script.sh

# Works: the explicit interpreter sidesteps the wrapper's exec restrictions
/bin/zsh -f ~/.local/bin/some-script.sh
```

Per [agent-defaults.md L25](../../../chezmoi/dot_config/instructions/agent-defaults.md), retry with the explicit interpreter form *before* assuming a real file-permission problem.

## When the problem isn't shell

If you've reached this skill but none of the above patterns match, the problem probably isn't shell-level. Check:

- Is the binary actually installed? `command -v <name>` (use `command`, not `which` — `which` is itself shell-specific in zsh).
- Is `$PATH` what you expect? Aliases and `direnv` can mutate it inside the shell only.
- Is the working directory what you expect? Shell history and IDE harnesses can confuse `cwd`.
- Is the file mode actually executable? `stat -c '%A %n' <file>` — GNU syntax on every host here, including macOS (see the `stat` section above; BSD `-f` syntax breaks).

After ruling those out, check [ops-nix-pitfalls](../ops-nix-pitfalls/SKILL.md) for nix-specific traps that surface as shell errors.

## Quick checklist

- No `status`/`path`/`cdpath`/`fpath`/`manpath` used as a plain variable name.
- Variable expansions and file paths quoted (`"$var"`); literal `==`/`===` quoted.
- Aliases bypassed (`/bin/cat`, `/bin/ls`, `command <name>`) when exact output matters.
- Long/nested/JSON payload moved to a script file instead of retried inline.
- `gh api graphql` / long `jq` filters file-backed up front (gh-graphql-jq-pipelines).
- Credentials loaded via `kac` / cache; never echoed into output.

## References

- [chezmoi/dot_config/instructions/agent-defaults.md](../../../chezmoi/dot_config/instructions/agent-defaults.md) — the source instruction file these patterns are codified from.
- [home-manager/zsh.nix](../../../home-manager/zsh.nix) — the alias definitions.
- [gh-graphql-jq-pipelines](../gh-graphql-jq-pipelines/SKILL.md) — the file-backed shape for `gh api graphql` + `jq`.
