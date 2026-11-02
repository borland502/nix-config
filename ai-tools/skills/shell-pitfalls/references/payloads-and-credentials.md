# Heavy quoting → write a script file

Before running commands containing JSON payloads, inline scripts or heavy quoting, write a named script under `~/.cache/codex` and execute that file. File-backing is a first-run precondition. If an existing shared shell has already mangled a command, stop reusing it and run the file in an isolated shell.

```bash
# Avoid: nested shell and JSON quoting
zsh -c "curl -X POST https://api.example.com/foo -H 'Content-Type: application/json' -d '{\"key\":\"value with spaces\"}'"

# Right: file-based, no quote escaping
mkdir -p ~/.cache/codex
/bin/cat > ~/.cache/codex/post.sh <<'SCRIPT'
#!/usr/bin/env zsh
curl -X POST https://api.example.com/foo \
  -H 'Content-Type: application/json' \
  -d '{"key":"value with spaces"}'
SCRIPT
chmod +x ~/.cache/codex/post.sh
~/.cache/codex/post.sh
```

The file form is re-runnable and edit-friendly. Do not assume a hook captures file contents; retain the named script alongside its result evidence.

For bounded CloudWatch captures, use
`aws-log-fetch LOG_GROUP --start ISO8601 --end ISO8601 --output FILE`
with a file under `~/.cache/<agent>/` and optional `--request-id ID`.
It refreshes credentials, handles the CLI arguments and pagination, and saves
validated JSON privately. `aws-lambda-metrics FILE` extracts generic Lambda
REPORT metrics offline. Use a custom script only for queries these interfaces
cannot express.

The other recurring offender is **`aws logs` + `jq` one-shots**: a CloudWatch
log-stream name contains `[$LATEST]` (dollar + brackets — both shell-active),
the filter pattern needs its own quotes, and the whole thing gets wrapped in
`zsh -lc '… kac ensure >/dev/null && aws logs …'`. This shape is vulnerable to shell expansion; inspect actual stderr before attributing a cause. Put the `aws logs filter-log-events` invocation and filter in a script file before its first run.

```bash
# Wrong: [$LATEST] and the pattern fight three quoting layers deep
zsh -lc "source ~/.local/bin/kac ensure >/dev/null && aws logs filter-log-events --log-group-name '/aws/lambda/foo' --log-stream-names '2026/06/30/[\$LATEST]abc' --filter-pattern '\"ERROR\"' | jq '.events[].message'"

# Right: script file — single quoting layer, re-runnable, log-friendly
/bin/cat > ~/.cache/codex/logscan.sh <<'SCRIPT'
#!/usr/bin/env bash
source ~/.local/bin/kac ensure >/dev/null || exit 1
aws logs filter-log-events \
  --log-group-name '/aws/lambda/foo' \
  --log-stream-names '2026/06/30/[$LATEST]abc' \
  --filter-pattern '"ERROR"' | jq '.events[].message'
SCRIPT
bash ~/.cache/codex/logscan.sh
```

The persistent [terminal defaults](../../../../chezmoi/dot_config/instructions/agent-defaults.md) require file-backed scripts before JSON payloads, inline scripts or heavy quoting; do not retry inline first.

For the specific case of `gh api graphql` calls and long/nested `jq` filters — the highest-frequency offender — file-backing is required before the first run. See [gh-graphql-jq-pipelines](../../gh-graphql-jq-pipelines/SKILL.md) for the sanctioned `.graphql` + `.jq` file shape and the four recurring failure signatures.

## AWS / Kion credential safety

When the local environment uses Kion, load temporary AWS credentials with `source ~/.local/bin/kac ensure` (or read `~/.cache/kion-aws-cache/`) rather than the frequently-stale `~/.aws/credentials` / `AWS_PROFILE`. Treat any value read from a credentials file as a secret — never echo it into command output or a summary.

For CloudFormation failure triage, prefer
`aws-stack-triage <stack> [--region REGION]`. It runs `kac ensure` itself and
provides summary, nested-stack, and failed-event views without another ad-hoc
AWS/jq loop. Use `--summary`, `--nested`, `--failures`, `--resources`, or
`--all` to narrow or expand the read-only output. When nested resources are
requested, failed events from direct child stacks are included. Kion refresh
failures route to `sec-kion-credential-recovery`; other credential lookup
questions route to `sec-credentials`.

When actual command stderr reports `ExpiredToken`, `InvalidClientTokenId` or
`Unable to locate credentials`, investigate credential lifecycle — go to
[sec-credentials](../../sec-credentials/SKILL.md) for the full lookup precedence
(sops → XDG config → legacy paths) instead of debugging the command.
