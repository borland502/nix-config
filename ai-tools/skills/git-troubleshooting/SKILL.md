---
name: git-troubleshooting
description: Use when a git command fails and the message names a revision, object, path, or repository — "not a git repository", "bad object", "ambiguous argument", "Needed a single revision", "Invalid revision range", "pathspec did not match any files", "path does not exist in", "detached HEAD" — or when a repo is stuck mid-cherry-pick/rebase/merge and you must choose continue, skip, or abort. For branching strategy, commit conventions, or shipping finished work use the git-finish-branch and git-request-review skills instead.
---

# Git Troubleshooting

Git error text names the *symptom* (a revision, an object, a path) but almost
never the *cause*, which is usually one of: the command ran in the wrong
repository, the revision came from somewhere else, or the shell mangled the
argument before git saw it. Diagnose in that order.

## First move: confirm where the command actually ran

`fatal: not a git repository (or any of the parent directories): .git` is the
most common failure in this repo's logs, and it is never a git problem — the
process was in the wrong directory. Agent sessions accumulate `cd` calls into
cache dirs, worktrees, and `/tmp`, and a later `cd` can silently fail.

**Rule: pass the repo explicitly rather than relying on cwd.**

```bash
# Fragile: depends on every prior cd having succeeded
cd "$WT" && git log --oneline -5

# Robust: -C is checked by git itself and fails loudly on a bad path
git -C "$WT" log --oneline -5
```

`git -C` works for every subcommand and survives a `cd` that didn't happen.

## `fatal: bad object <sha>`

The object is well-formed but **not in this repository**. It parsed as a sha, so
git got past argument validation and failed at lookup. Three causes, in
descending order of likelihood:

| Cause | Check |
|---|---|
| Sha came from a *different* repo or worktree | `git -C <repo> cat-file -t <sha>` in each candidate |
| History was rewritten (`filter-branch`, `rebase`, amend) and the sha is pre-rewrite | `git reflog --all \| rg <short-sha>` |
| Object is in a remote you haven't fetched | `git fetch origin <ref>` then retry |

Observed case: `git --no-pager diff --stat <sha1> <sha2>` run from the main
checkout with shas copied from a worktree's log. Both failed as `bad object`.

## Revision-syntax errors usually mean the shell, not git

These four messages share one root cause more often than not — **the argument
never reached git in the shape you wrote it**:

```
fatal: ambiguous argument 'origin/main origin/dev6...': unknown revision or path
fatal: ambiguous argument '^{tree}': unknown revision or path
fatal: empty string is not a valid pathspec
fatal: Needed a single revision
```

An error quoting *two space-separated values inside one set of quotes* is the
tell: zsh does not word-split unquoted expansions, so `set -- $pair` puts the
whole pair in `$1` and leaves `$2` empty. **REQUIRED BACKGROUND:** see
[shell-pitfalls](../shell-pitfalls/SKILL.md) § "zsh does not word-split
unquoted expansions" before rewriting the git command — the git command is
usually correct.

Genuine revision-syntax problems worth knowing:

- `A...B` (three dots) is symmetric difference; `A..B` is two-dot range. `git
  merge-base` wants two separate arguments, not a range.
- `Invalid revision range <sha>..<sha>` — one endpoint is unreachable from the
  other, or they are in unrelated histories (common across worktrees).
- `--follow requires exactly one pathspec` — `git log --follow` takes a single
  file; it cannot take a glob or a directory.

## `pathspec` vs `path`: two different questions

The wording distinguishes *where* git looked, and they need opposite fixes:

```
fatal: pathspec 'tests/e2e/helpers.ts' did not match any files
  → looked in the working tree / index. The file isn't checked out here.
    Wrong branch, wrong worktree, or the file is untracked and you used a
    command that only sees tracked files.

fatal: path 'scripts/kion-refresh' does not exist in '<sha>'
  → looked inside that specific commit. The file exists now but not there
    (added later, or renamed). Use `git log --all --follow -- <path>` to find
    when it appeared, or `git show <sha>:<correct-old-path>`.
```

## Detached HEAD, especially in worktrees

`git worktree list` showing `(detached HEAD)` is the single most frequent state
in this repo's logs. Worktrees created for agent sessions are often detached, so
commits made there belong to **no branch** and vanish from `git branch` and
`git log <branch>` — they are reachable only by sha or reflog.

```bash
# Are we detached?
git -C "$WT" symbolic-ref -q HEAD || echo "DETACHED"

# Rescue commits made while detached
git -C "$WT" branch recovered-work HEAD    # name it before doing anything else
git -C "$WT" reflog -20                    # if HEAD already moved
```

Name the branch *first*. A later `checkout`/`switch` in a detached worktree
leaves the commits unreferenced and only the reflog can find them.

For worktree layout and lifecycle, see
[git-worktrees](../git-worktrees/SKILL.md).

## Stuck mid-operation: continue, skip, or abort

Conflict hints (`git rebase --continue`, `git cherry-pick --skip`) tell you the
options but not which operation is in flight, and running the wrong one errors
out. Ask git:

```bash
# Long status names the operation. --short/--porcelain does NOT — it prints
# only "## main" and "UU <file>", which cannot tell a cherry-pick from a merge.
git status | head -2
# → "You are currently cherry-picking commit cf9776c."

# Machine-readable: check for the marker file in the real git dir.
ls "$(git rev-parse --git-dir)" | rg 'CHERRY_PICK_HEAD|MERGE_HEAD|REBASE_HEAD|rebase-merge|rebase-apply'
```

Use `git rev-parse --git-dir`, not a literal `.git/`. **In a worktree `.git` is
a regular file**, not a directory, so `ls .git/CHERRY_PICK_HEAD` fails there —
precisely where agent sessions do most of their conflicted work.

| Situation | Action |
|---|---|
| Conflicts resolved, want the commit | `git add <paths>` then `<op> --continue` |
| This commit's changes are already present upstream | `<op> --skip` |
| Want the pre-operation state back | `<op> --abort` — read the warning below first |

### `--abort` silently deletes work you staged during the operation

`--abort` restores the pre-operation state, and it does **not** warn or refuse
when that means destroying files. Verified behavior:

| File | Fate after `cherry-pick --abort` |
|---|---|
| Added and `git add`-ed *during* the conflicted operation | **Deleted.** Exit code 0, no warning |
| Uncommitted edit to a file tracked *before* the operation began | Survives |

So a note, scratch script, or partial fix you created while resolving conflicts
is gone. Before any `--abort`, move that work out of the repo (or
`git stash -u`) — the reflog cannot recover a file that was never committed.

**Never** resolve a conflict by checking out one side wholesale (`git checkout
--ours <file>`) without reading the diff — it silently drops the other side's
changes. Verify with `git diff --check` and a build before continuing.

## When it isn't git

- Push rejected / auth failures / API 4xx → [github-ops](../github-ops/SKILL.md).
- The command was assembled with quoting or expansion →
  [shell-pitfalls](../shell-pitfalls/SKILL.md).
- Recurring across sessions → `cache-scan --classify` groups them; see
  [ops-cache-scan](../ops-cache-scan/SKILL.md).
- Cause still unclear after the checks above →
  [flow-systematic-debugging](../flow-systematic-debugging/SKILL.md).

## Quick checklist

- [ ] `git -C <repo>` used instead of trusting cwd.
- [ ] Sha verified to exist in *this* repo (`git cat-file -t`) before blaming git.
- [ ] Error quoting two values in one pair of quotes → fix the shell, not the revision.
- [ ] `pathspec` vs `path` distinguished before choosing a fix.
- [ ] Detached-HEAD commits given a branch name before any further checkout.
- [ ] In-flight operation identified via long `git status` (not `--short`) before
      `--continue`/`--abort`.
- [ ] Work staged during a conflicted operation moved out of the repo before
      `--abort` — abort deletes it without warning.
