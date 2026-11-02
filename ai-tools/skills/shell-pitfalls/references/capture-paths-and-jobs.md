# Piping non-JSON into `jq`

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

Per [agent-defaults.md L25](../../../../chezmoi/dot_config/instructions/agent-defaults.md), retry with the explicit interpreter form *before* assuming a real file-permission problem.

## Empty command substitution poisons the next command

For uncertain source filenames, let ripgrep match paths instead of the shell:
`rg -n 'pattern' src -g '*worker*'`. Use `rg --files src -g '*worker*'` to
discover candidates first. This handles zero matches without a zsh glob error
and avoids repeating the same failed wildcard command in a different form.

`$(...)` that finds nothing yields an empty string, and the empty string is
still passed as an argument. The failure surfaces one command later, wearing
the wrong tool's name:

```bash
F=$(fd -t f 'lambda_uri.py' "$S" | head -1)
sed -n '1,40p' "$F"        # → "sed: : No such file or directory"
```

`sed` is not the problem; `fd` matched nothing. Same shape produces
`ls: cannot access '': …`, `Is a directory: '/tmp/r.txt'` (the variable was
empty so a directory path got reused), and `cd: no such file or directory`.

```bash
# Guard: fail loudly at the point the assumption breaks
F=$(fd -t f 'lambda_uri.py' "$S" | head -1)
[ -n "$F" ] || { echo "no lambda_uri.py under $S" >&2; exit 1; }
```

Guard every `$(...)` whose result becomes a path, an ARN, an ID, or a URL —
especially inside a chain, where the empty value travels several steps before
anything complains.

## Relative `cd` does not survive between tool calls

The Bash tool keeps a working directory across calls, but a one-shot `cd` in a
compound command does not always stick, and a *relative* `cd` in the next call
then resolves against the wrong parent:

```bash
# Call 1
cd /repo/root && ./do-thing
# Call 2 — assumes call 1's cwd persisted
cd audits/rc-validation && pytest
# → "(eval):cd:1: no such file or directory: audits/rc-validation"
```

Use an absolute path in every `cd`, or set a variable once and reuse it
(`W=/repo/root; cd "$W/audits/rc-validation"`). Never let one call's `cd`
be the precondition for the next call's relative path.

## Bounded waits for jobs

Use the current harness's background-job notification or bounded wait API;
keep each wait within its supported duration and communication budget. For
GitHub Actions use `monitor-gh-run RUN_ID`. Do not busy-spin or prepend a long
foreground sleep to a status check. Keep the job ID and explicit cwd so a later
turn can resume monitoring without restarting the job.

## The nix `python3` / `node` have no third-party libraries

The interpreters on `PATH` come from the nix profile with a bare stdlib. An
inline script that imports anything external dies at the import:

```bash
python3 -c "import yaml; …"    # → ModuleNotFoundError: No module named 'yaml'
node shot.js                   # → Error: Cannot find module 'playwright'
```

This is not a broken install and `pip install` is the wrong fix (the store path
is read-only). Options, in order of preference:

1. **Use the CLI that already exists** — `yq` / `dasel` for YAML and TOML, `jq`
   for JSON, `rg` for extraction. Almost every inline `import yaml` should have
   been a `yq` filter.
2. **Ask nix for the dependency for one command**:
   `nix-shell -p 'python3.withPackages(ps: [ps.pyyaml])' --run 'python3 script.py'`
3. **Run inside the project's own environment** — `.venv/bin/python`,
   `npx --yes <pkg>`, or the repo's `uv run` / `bun` entry point — when the
   library is a project dependency rather than a one-off need.
