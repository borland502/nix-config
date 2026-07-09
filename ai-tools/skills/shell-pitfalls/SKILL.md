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

The other recurring offender is **`aws logs` + `jq` one-shots**: a CloudWatch
log-stream name contains `[$LATEST]` (dollar + brackets — both shell-active),
the filter pattern needs its own quotes, and the whole thing gets wrapped in
`zsh -lc '… kac ensure >/dev/null && aws logs …'`. Every observed failure of
this shape was quoting rot, not AWS. Same rule: put the `aws logs
filter-log-events` invocation (and any `jq` filter) in a script file first.

```bash
# Wrong: [$LATEST] and the pattern fight three quoting layers deep
zsh -lc "source ~/.local/bin/kac ensure >/dev/null && aws logs filter-log-events --log-group-name '/aws/lambda/foo' --log-stream-names '2026/06/30/[\$LATEST]abc' --filter-pattern '\"ERROR\"' | jq '.events[].message'"

# Right: script file — single quoting layer, re-runnable, log-friendly
cat > ~/.cache/claude/logscan.sh <<'SCRIPT'
#!/usr/bin/env bash
source ~/.local/bin/kac ensure >/dev/null || exit 1
aws logs filter-log-events \
  --log-group-name '/aws/lambda/foo' \
  --log-stream-names '2026/06/30/[$LATEST]abc' \
  --filter-pattern '"ERROR"' | jq '.events[].message'
SCRIPT
bash ~/.cache/claude/logscan.sh
```

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

## Subshell PATH loss

`env -i`, `sudo`, and a bare `zsh -c '…'` (no `-l`) do **not** inherit the nix
profile + Homebrew `PATH`. Tools that resolve fine interactively — GNU `stat`,
`timeout`, `gkion`, `aws` — suddenly report `command not found`, and it looks
like a missing install when it's a missing PATH.

```bash
# Wrong: bare zsh -c gets the system default PATH — timeout/aws are not on it
zsh -c 'timeout 30 aws s3 ls'

# Right: login shell pulls in the nix/Homebrew profile
zsh -lc 'timeout 30 aws s3 ls'

# Also right: stay in the current (already-provisioned) shell, or pass PATH /
# absolute paths explicitly when a stripped environment is unavoidable
env -i HOME="$HOME" PATH="$PATH" bash -c 'timeout 30 aws s3 ls'
```

The `kac` credential helper PATH-hardens its own refresh internally, but
nothing else on your command line gets that rescue. If a "not found" error
names a tool you know is installed, check *which shell* is resolving it before
reinstalling anything. This is also why the GNU-vs-BSD `stat` trap (above)
sometimes appears to flip: a stripped PATH can fall back to `/usr/bin/stat`
(BSD) while the interactive shell resolves the nix GNU one.

## zsh nullglob: "no matches found" aborts the command

Unlike bash, zsh **errors out** when a glob matches nothing — the command never
runs at all:

```zsh
# Aborts with "zsh: no matches found: docker-compose*.yml" if none exist
ls docker-compose*.yml

# Guard 1: (N) qualifier — expands to nothing instead of erroring
ls docker-compose*.yml(N)

# Guard 2: let fd do the matching (no shell glob involved)
fd -g 'docker-compose*.yml' --max-depth 1

# Guard 3: test existence before globbing in scripts
for f in docker-compose*.yml(N); do …; done
```

Observed failures: `docker-compose*.yml` and `~/.config/ops-agent/config*`
with no match killed whole `&&` chains. In `zsh -c` one-shots prefer `fd`; in
committed zsh scripts add `setopt nullglob` (or the `(N)` qualifier per-glob).
Bash behaves differently (passes the literal pattern through), which is why a
snippet tested in bash breaks under zsh.

## Piping non-JSON into `jq`

`jq: parse error: Invalid numeric literal` almost never means malformed JSON —
it means the payload isn't JSON at all: an HTML 401/error page from an
unauthenticated `curl`, a log line, or an empty body. A related trap: a filter
that yields `null` gets substituted into a later command as the literal string
`null` (`bash: null: No such file or directory`).

```bash
# Wrong: a 401 HTML page goes straight into jq
curl -s "$JIRA_URL/rest/api/2/issue/KEY-1" | jq '.fields.status.name'

# Right: fail on HTTP errors so jq only ever sees a real body
curl -fsS -H "Authorization: Bearer $TOKEN" \
  "$JIRA_URL/rest/api/2/issue/KEY-1" | jq -r '.fields.status.name // empty'
```

Rules: `curl -fsS` (fail on 4xx/5xx) whenever the output feeds `jq`; give
lookups a `// empty` (or explicit default) so `null` never leaks into a path
or argument; when the payload's shape is unknown, `gron` it first. If the
`jq` filter itself is long or quote-nested, file-back it
(gh-graphql-jq-pipelines).

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
- Credentials loaded via `kac ensure` (exit-code gated); never echoed into output.
- Subshells launched with `-l` / explicit `PATH` when nix-profile tools are needed.
- zsh globs guarded (`(N)`, `fd`, or `setopt nullglob`) so no-match doesn't abort.

## References

- [chezmoi/dot_config/instructions/agent-defaults.md](../../../chezmoi/dot_config/instructions/agent-defaults.md) — the source instruction file these patterns are codified from.
- [home-manager/zsh.nix](../../../home-manager/zsh.nix) — the alias definitions.
- [gh-graphql-jq-pipelines](../gh-graphql-jq-pipelines/SKILL.md) — the file-backed shape for `gh api graphql` + `jq`.
