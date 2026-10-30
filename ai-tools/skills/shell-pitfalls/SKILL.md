---
name: shell-pitfalls
description: Use when constructing shell commands with globs, URL queries, multi-field records or long-running jobs, or diagnosing quoting, alias, environment, GNU/BSD flag or zsh expansion failures.
---

# Shell pitfalls

Use the observed command and result to distinguish shell expansion, environment,
tool syntax and application failures. Inspect recent cached evidence first with
`cache-scan --session ID --transcript`; a quoted error in a successful file read
does not establish a failed invocation. Preserve the actual exit status and
stderr. Route a confirmed application problem to its owner after ruling out
shell behavior.

## Before constructing the command

- Run project commands through `direnv exec ROOT COMMAND` when an allowed
  ancestor `.envrc` exists. A working directory or login shell does not load it.
- Use explicit absolute working directories for every tool invocation; `cd`
  does not persist across calls. Validate substituted paths, IDs and ARNs are
  nonempty before passing them onward.
- Quote paths, expansions and URL/query arguments containing `?`, `*`, `[` or
  literal `~`. Let `fd` or `rg --glob` handle optional matches. In zsh an
  unmatched glob aborts before the command runs, even inside a pipeline that
  subsequently prints zero. Do not rely on `(N)` in an agent shell with
  `nobareglobqual`.
- Use arrays or explicit field extraction for multi-field records. zsh does
  not implicitly split `$pair`; one combined git ref and an empty second ref
  often indicate this cause. Do not globally enable `SH_WORD_SPLIT`.
- Never assign shell variables named `status`, `path`, `cdpath`, `fpath` or
  `manpath`. Use `exit_code`, `p` or `result`. Quote literal `==`/`===` data.

## Select the relevant recipe

Read only the matching reference before applying a conditional recipe:

| Symptom or operation | Reference |
| --- | --- |
| Aliased output or special variable | [Aliases and runtime](references/aliases-and-runtime.md) |
| Nested JSON/quoting, AWS logs or credentials | [Payloads and credentials](references/payloads-and-credentials.md) |
| GNU/BSD flags, PATH loss, zsh local exports, rg flags | [Tool dialects and environment](references/tool-dialects-and-environment.md) |
| Optional paths, URL queries, multi-field loops | [Globs and field splitting](references/globs-and-field-splitting.md) |
| jq input, empty substitution, cwd, jobs or missing modules | [Capture, paths and jobs](references/capture-paths-and-jobs.md) |

## Execution rules

Use `/bin/cat`, `/bin/ls` or `command` when exact output must bypass aliases.
Check `command -v` and the actual tool dialect before changing valid logic;
these managed hosts normally resolve GNU coreutils even on macOS. Export a
function-local environment variable explicitly in zsh if children need it.

Put JSON payloads, inline scripts and heavy quoting in a named script under
`~/.cache/codex` before execution. Stop retrying a mangled shared shell; use an
isolated shell. Every `gh api graphql` call and jq filter over roughly 200
characters or with nested escaped quotes must be file-backed on its first run;
use [gh-graphql-jq-pipelines](../gh-graphql-jq-pipelines/SKILL.md).

Validate HTTP success and content before jq; use `jq -e` for required values.
Prefer installed structured-data CLIs or the project environment over importing
third-party modules into bare Nix Python/Node. Use the harness's bounded job wait
or a purpose-built monitor such as `monitor-gh-run`, keeping updates possible;
do not busy-spin or put a long foreground sleep before another check.

Confirmed AWS credential failures route to
[sec-credentials](../sec-credentials/SKILL.md) and Kion recovery when applicable;
never print credentials. Prefer `aws-stack-triage` and `aws-log-fetch` to ad hoc
AWS/jq loops. Git errors with intact arguments route to
[git-troubleshooting](../git-troubleshooting/SKILL.md); Nix failures route to
[ops-nix-pitfalls](../ops-nix-pitfalls/SKILL.md).
