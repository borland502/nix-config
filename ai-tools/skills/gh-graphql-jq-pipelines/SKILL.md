---
name: gh-graphql-jq-pipelines
description: Use BEFORE composing any `gh api graphql` call, or any `jq` filter longer than ~200 chars or containing nested escaped quotes. The only sanctioned shape is file-backed — query in a `.graphql` file, filter in a `.jq` file, variables passed with `-F`. Covers the four recurring failures (RCURLY quote drift, `$var is not defined`, `Variable declared but not used`, nested `\"n/a\"` escape rot) and the canonical fix for each. Reach for the `gh-graphql` helper to do it in one command.
---

# gh api graphql + jq pipelines

Inline `gh api graphql ... --jq '...'` invocations with nested double-quote
escaping are a recurring, fully-avoidable source of failed commands. Each
failure costs at least one retry round-trip (capture → diagnose → re-quote →
re-run), and the agent typically re-emits the whole inline string to "fix" it —
doubling the token cost. There is exactly one correct shape; use it from the
**first** run, not after a failure.

## The only sanctioned shape

Write the GraphQL document and the jq filter to files under `~/.cache/<agent>/`,
then reference them. Do **not** build either as an inline shell-quoted string.

```bash
mkdir -p ~/.cache/claude

# 1. Query → a .graphql file (Edit/Write tool, no shell quoting at all)
cat > ~/.cache/claude/pr2244-threads.graphql <<'GRAPHQL'
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 50) {
        nodes {
          isResolved
          comments(first: 1) { nodes { body author { login } } }
        }
      }
    }
  }
}
GRAPHQL

# 2. jq filter → a .jq file (again, no shell quoting)
cat > ~/.cache/claude/pr2244-threads.jq <<'JQ'
.data.repository.pullRequest.reviewThreads.nodes[]
| {resolved: .isResolved, author: (.comments.nodes[0].author.login // "n/a")}
JQ

# 3. One call: query via -F query=@file, vars via -F, filter via --jq "$(cat …)"
gh api graphql \
  -F query=@$HOME/.cache/claude/pr2244-threads.graphql \
  -F owner=Enterprise-CMCS -F repo=mdp-application -F number=2244 \
  --jq "$(cat $HOME/.cache/claude/pr2244-threads.jq)"
```

Prefer the **`gh-graphql` helper** (`~/.local/bin/gh-graphql`), which auto-names
and timestamps both files under `~/.cache/<agent>/` so the workflow is a single
command and the inputs survive for later forensics:

```bash
gh-graphql pr2244-threads ~/.cache/claude/pr2244-threads.graphql \
  --jq ~/.cache/claude/pr2244-threads.jq \
  -F owner=Enterprise-CMCS -F repo=mdp-application -F number=2244
```

Key rules:

- GraphQL **variables** (`$owner`, `$number`) are declared in the query's
  signature and supplied with `-F key=value`. Integers need `-F number=2244`
  (gh infers the type); strings are passed the same way.
- The **jq filter** is a *separate* layer that runs on the JSON response. Its
  parameters are passed with `--jq` only; `jq`'s own `--arg`/`--argjson` are
  **not** available through `gh api graphql --jq`. If the filter needs a value,
  bake it into the `.jq` file or template it in before the call — do not try to
  pass `--arg` to `gh`.
- `gh api graphql` returns the body under `.data`; a failed selection yields
  `null`, so guard with `// "n/a"` or `// empty` before iterating.

## The four recurring failures and their fixes

### 1. `gh: Expected one of SCHEMA, SCALAR … actual: RCURLY ("}")`

The inline GraphQL document closed too early — the shell ate a `{`/`}` boundary
inside the heavily-quoted string. **Fix:** move the query into a `.graphql` file
and pass `-F query=@file`. The file has no shell-quoting context, so braces
survive verbatim.

### 2. `jq: error: syntax error … unexpected INVALID_CHARACTER`

The jq filter was passed as a single shell-quoted string and a nested escape
(e.g. `\"n/a\"`) flipped because the surrounding quoting context drifted.
**Fix:** put the filter in a `.jq` file with real unescaped quotes
(`"n/a"`), and pass it as `--jq "$(cat file.jq)"`.

### 3. `jq: error: $commentId is not defined`

`--arg commentId N` was passed to `gh`, but `gh api graphql --jq` does not
forward jq `--arg`/`--argjson` to the filter — the binding never reaches jq.
**Fix:** either bake the literal into the `.jq` file, or, if it must vary, use a
GraphQL variable (`-F commentId=N`) and select it from `.data` rather than
referencing a jq variable.

### 4. `gh: Variable $commentId is declared by anonymous query but not used`

Over-correction from #3: a GraphQL `$commentId` was declared in the signature
but never wired into the selection set, so gh rejects it (and the response body
is `null`, which then blows up the downstream jq with `Cannot iterate over
null`). **Fix:** every declared GraphQL variable must be *referenced* in the
query body (e.g. `pullRequest(number: $number)`), and every iterated jq path
must be guarded with `// empty`.

## When to reach for this skill

Stop and follow this shape **before the first run** whenever you are about to:

- compose any `gh api graphql` call (with or without `--jq`), or
- write an inline `jq` filter longer than ~200 chars, or
- write any inline `jq`/GraphQL string containing nested escaped quotes
  (`\"`, `\\\"`).

There is no "try inline first, fall back on failure" path — file-backing is the
default, not the recovery.

## References

- [shell-pitfalls](../shell-pitfalls/SKILL.md) — the general "heavy quoting →
  write a script file" rule this skill specializes for the gh/jq case.
- [chezmoi/dot_config/instructions/agent-defaults.md](../../../chezmoi/dot_config/instructions/agent-defaults.md)
  — the always-on precondition that points here.
- `~/.local/bin/gh-graphql` — the helper that automates the file-backed shape.
