---
name: git-worktrees
description: Use when starting feature work that needs isolation from current workspace or before executing implementation plans - ensures an isolated workspace exists in the one shared worktree location every harness and the editor agree on
---

# Using Git Worktrees

## Overview

Ensure work happens in an isolated workspace, in the one location every harness and the editor agree on.

**Core principle:** Detect existing isolation first. Then pick the location yourself and create the worktree with git. Then let a native tool bind the session to it. Never let the harness pick the location — that is what scatters a repository's worktrees across per-harness directories nobody can enumerate.

**Announce at start:** "I'm using the git-worktrees skill to set up an isolated workspace."

## Step 0: Detect Existing Isolation

**Before creating anything, check if you are already in an isolated workspace.**

```bash
ROOT=$(cd "$(git rev-parse --show-toplevel)" 2>/dev/null && pwd -P)
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
CURRENT_BRANCH=$(git branch --show-current)
```

**Submodule guard:** `GIT_DIR != GIT_COMMON` is also true inside git submodules. Before concluding "already in a worktree," verify you are not in a submodule:

```bash
# If this returns a path, you're in a submodule, not a worktree — treat as normal repo
git rev-parse --show-superproject-working-tree 2>/dev/null
```

**If `GIT_DIR != GIT_COMMON` (and not a submodule):** You are already in a linked worktree. Skip to Step 2 (Project Setup). Do NOT create another worktree.

Report with branch state:
- On a branch: "Already in isolated workspace at `<path>` on branch `<name>`."
- Detached HEAD: "Already in isolated workspace at `<path>` (detached HEAD, externally managed). Branch creation needed at finish time."

**If `GIT_DIR == GIT_COMMON` (or in a submodule):** You are in a normal repo checkout.

Has the user already indicated their worktree preference in your instructions? If not, ask for consent before creating a worktree:

> "Would you like me to set up an isolated worktree? It protects your current branch from changes."

Honor any existing declared preference without asking. If the user declines consent, work in place and skip to Step 2.

## Step 1: Create Isolated Workspace

**Location is chosen first, on every harness. Then the worktree is created.
Then the session is bound to it.** Do these three sub-steps in order.

Every harness must land worktrees in the *same* directory, so a native tool
that also picks the location is used only for the binding in Step 1c — never to
place the directory. A harness-chosen location is what splits one repository's
worktrees across `.claude/worktrees/`, a per-harness cache, and the repo, until
no tool and no human can see them all in one place.

### 1a. Directory Selection

Follow this priority order. Explicit user preference always beats observed filesystem state.

1. **Check your instructions for a declared worktree directory preference.**
   Use it unless it is repository-local and `git check-ignore -q` does not
   confirm it is already ignored. Reject an unignored repository-local
   preference; do not alter repository ignore rules.

2. **`.worktrees/` at the repository root — the default.** Use it whenever
   `git check-ignore -q .worktrees` succeeds, and **create it if it does not
   exist yet**; an ignored directory is safe to create, and waiting for someone
   else to create it first is what scattered these worktrees to begin with.
   `.worktrees/` is ignored globally here (`~/.config/git/ignore`, set by
   `programs.git.ignores` in the nix-config repo), so this normally succeeds in
   every repository, including ones whose own `.gitignore` says nothing.

   If a repository somehow un-ignores it, fall back to `worktrees/` only when
   `git check-ignore -q worktrees` succeeds and it already exists.

3. **Otherwise, outside the repository:**
   `${XDG_CACHE_HOME:-$HOME/.cache}/git-worktrees/<repository>-<root-hash>`.
   The creation block calculates the physical root and collision-safe cache
   location itself. This path is deliberately harness-neutral: a Claude session
   and a Copilot session working the same repository must arrive at the same
   directory, so it is never `.../claude/...` or `.../copilot/...`.

**Why critical:** A repository-local worktree must already be ignored to
prevent accidental tracking. Cache fallback preserves that safety without
modifying repository files.

**This directory is also what the editor uses.** The
`jackiotyu.git-worktree-manager` VS Code extension is configured to propose
`$BASE_PATH/.worktrees/$REF_NAME` (see
`home-manager/lib/code-editor-user-settings.nix`), so a worktree made by hand
in the editor lands beside the ones made here. Changing the priority above
without changing that setting re-splits them.

### 1b. Create the Worktree

Run this entire block in one shell call so selection state cannot be lost
between turns. Replace `BRANCH_NAME`; set `PREFERRED_LOCATION` only when
instructions declare one.

```bash
set -euo pipefail
BRANCH_NAME='<requested-feature-branch>'
PREFERRED_LOCATION=''
ROOT=$(cd "$(git rev-parse --show-toplevel)" && pwd -P)

if [[ -n "$PREFERRED_LOCATION" ]]; then
  case "$PREFERRED_LOCATION" in
    /*) ;;
    *) PREFERRED_LOCATION="$ROOT/$PREFERRED_LOCATION" ;;
  esac
  PREFERRED_LOCATION=$(realpath -m -- "$PREFERRED_LOCATION")
  case "$PREFERRED_LOCATION/" in
    "$ROOT/"*)
      git check-ignore -q "$PREFERRED_LOCATION/" || {
        echo "Repository-local worktree path is not ignored: $PREFERRED_LOCATION" >&2
        exit 1
      }
      ;;
  esac
  LOCATION="$PREFERRED_LOCATION"
elif git check-ignore -q "$ROOT/.worktrees/"; then
  # No -d test: an ignored .worktrees/ is created on first use. mkdir -p below
  # does it. Requiring it to pre-exist is what pushed sessions to the cache.
  LOCATION="$ROOT/.worktrees"
elif [[ -d "$ROOT/worktrees" ]] &&
  git check-ignore -q "$ROOT/worktrees/"; then
  LOCATION="$ROOT/worktrees"
else
  REPOSITORY=$(printf '%s' "$(basename "$ROOT")" |
    LC_ALL=C tr -cs '[:alnum:]._-' '-' | cut -c1-80)
  ROOT_HASH=$(printf '%s' "$ROOT" | git hash-object --stdin)
  CACHE_WORKTREE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/git-worktrees"
  mkdir -p "$CACHE_WORKTREE_ROOT"
  CACHE_WORKTREE_ROOT=$(cd "$CACHE_WORKTREE_ROOT" && pwd -P)
  LOCATION="$CACHE_WORKTREE_ROOT/${REPOSITORY}-${ROOT_HASH}"
  mkdir -p "$LOCATION"
  LOCATION_PHYSICAL=$(cd "$LOCATION" && pwd -P)
  [[ "$LOCATION_PHYSICAL" == "$LOCATION" ]] || {
    echo "Refusing redirected cache parent: $LOCATION" >&2
    exit 1
  }
fi

WORKTREE_PATH="$LOCATION/$BRANCH_NAME"
mkdir -p "$LOCATION"
[[ ! -e "$WORKTREE_PATH" && ! -L "$WORKTREE_PATH" ]] || {
  echo "Refusing existing or redirected worktree path: $WORKTREE_PATH" >&2
  exit 1
}
git worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME"
WORKTREE_PATH=$(cd "$WORKTREE_PATH" && pwd -P)
printf 'WORKTREE_PATH=%s\n' "$WORKTREE_PATH"
```

Use that printed absolute path explicitly as the working directory for every
later shell call. A terminal `cd` does not persist across tool invocations.

### 1c. Bind the Session to It

The worktree now exists at the shared location. If your harness has a native
worktree tool, use it here — to **enter** the directory Step 1b just created,
never to create one of its own.

**Claude Code (`EnterWorktree`):** pass `path`, never `name`.

```
EnterWorktree(path="<WORKTREE_PATH printed by Step 1b>")
```

`name` creates a *new* worktree under `.claude/worktrees/` and ignores your
chosen location entirely — that is the split this skill exists to prevent.
`path` moves the session into an existing worktree and only requires the path
to appear in `git worktree list`, which Step 1b guarantees. Two consequences
worth knowing:

- Entry by `path` must happen from the launch directory, before any other
  worktree switch this session. Once the session has switched worktrees, later
  `path` targets are restricted to `.claude/worktrees/`.
- `ExitWorktree` will **not** remove a worktree entered by `path`; use
  `action: "keep"` to return. Cleanup stays with the Cleanup block below, which
  is what you want — the directory is shared with other tools and other
  harnesses, not owned by one session.

**Copilot CLI and anything else with no native worktree tool:** there is
nothing to bind. Use the printed `WORKTREE_PATH` as the explicit working
directory for every later call, as above.

Either way both harnesses are now working in the same directory, and the VS
Code extension lists and creates alongside them.

#### Cleanup

The workflow owns cache-hosted worktrees under
`${XDG_CACHE_HOME:-$HOME/.cache}/git-worktrees/`; they are removed for
merge and discard choices. After the user chooses to merge or discard the
work, run this from any checkout of the same repository:

```bash
set -euo pipefail
BRANCH_NAME='<same-requested-feature-branch>'
MODE=merge
ROOT=$(git worktree list --porcelain |
  awk '/^worktree / { sub(/^worktree /, ""); print; exit }')
ROOT=$(cd "$ROOT" && pwd -P)
GIT_COMMON=$(cd "$ROOT" && cd "$(git rev-parse --git-common-dir)" && pwd -P)
REPOSITORY=$(printf '%s' "$(basename "$ROOT")" |
  LC_ALL=C tr -cs '[:alnum:]._-' '-' | cut -c1-80)
ROOT_HASH=$(printf '%s' "$ROOT" | git hash-object --stdin)
CACHE_WORKTREE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/git-worktrees"
CACHE_WORKTREE_ROOT=$(cd "$CACHE_WORKTREE_ROOT" && pwd -P)
EXPECTED_PARENT="$CACHE_WORKTREE_ROOT/${REPOSITORY}-${ROOT_HASH}"
EXPECTED_WORKTREE_PATH="$EXPECTED_PARENT/$BRANCH_NAME"
WORKTREE_PATH=$(cd "$EXPECTED_WORKTREE_PATH" && pwd -P)
[[ "$WORKTREE_PATH" == "$EXPECTED_WORKTREE_PATH" ]] || {
  echo "Refusing cleanup through redirected path: $EXPECTED_WORKTREE_PATH" >&2
  exit 1
}
WORKTREE_COMMON=$(cd "$WORKTREE_PATH" &&
  cd "$(git rev-parse --git-common-dir)" && pwd -P)
ACTUAL_BRANCH=$(git -C "$WORKTREE_PATH" symbolic-ref -q HEAD || true)
[[ "$WORKTREE_COMMON" == "$GIT_COMMON" ]] || {
  echo "Refusing to remove worktree owned by another repository" >&2
  exit 1
}
[[ "$ACTUAL_BRANCH" == "refs/heads/$BRANCH_NAME" ]] || {
  echo "Refusing to remove worktree on unexpected branch: $ACTUAL_BRANCH" >&2
  exit 1
}
cd "$ROOT"
case "$MODE" in
  merge) git worktree remove "$WORKTREE_PATH" ;;
  discard) git worktree remove --force "$WORKTREE_PATH" ;;
  *) echo "MODE must be merge or discard" >&2; exit 1 ;;
esac
git worktree prune
```

This recomputes the root-hash/branch path, rejects symlink redirection, and
verifies its Git common directory and branch instead of relying on variables
from the creation turn. Do not remove sibling cache worktrees.

**Sandbox fallback:** If `git worktree add` fails with a permission error (sandbox denial), tell the user the sandbox blocked worktree creation and you're working in the current directory instead. Then run setup and baseline tests in place.

## Step 2: Project Setup

Auto-detect and run appropriate setup:

```bash
# Node.js
if [ -f package.json ]; then npm install; fi

# Rust
if [ -f Cargo.toml ]; then cargo build; fi

# Python
if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
if [ -f pyproject.toml ]; then poetry install; fi

# Go
if [ -f go.mod ]; then go mod download; fi
```

## Step 3: Verify Clean Baseline

Run tests to ensure workspace starts clean:

```bash
# Use project-appropriate command
npm test / cargo test / pytest / go test ./...
```

**If tests fail:** Report failures, ask whether to proceed or investigate.

**If tests pass:** Report ready.

### Report

```
Worktree ready at <full-path>
Tests passing (<N> tests, 0 failures)
Ready to implement <feature-name>
```

## Quick Reference

| Situation | Action |
|-----------|--------|
| Already in linked worktree | Skip creation (Step 0) |
| In a submodule | Treat as normal repo (Step 0 guard) |
| Any harness | Pick location (1a) → `git worktree add` (1b) → bind (1c) |
| Native worktree tool available | Use it in 1c to *enter* the path from 1b, never to create |
| Claude Code | `EnterWorktree(path=…)`; `name` would force `.claude/worktrees/` |
| No native tool (Copilot CLI) | Nothing to bind; use the printed path explicitly |
| Explicit directory preference | Use it only if repository-local path is already ignored |
| `.worktrees/` ignored | Use it, creating it if absent — the default |
| `worktrees/` exists | Use it only if already ignored and `.worktrees/` did not qualify |
| No qualifying local directory | Use `${XDG_CACHE_HOME:-$HOME/.cache}/git-worktrees/<repository>-<root-hash>`, then append branch once |
| Directory not ignored | Reject repository-local path; use cache fallback |
| Merge or discard cache worktree | Recompute and validate its root-hash/branch path, remove it, then prune |
| Permission error on create | Sandbox fallback, work in place |
| Tests fail during baseline | Report failures + ask |
| No package.json/Cargo.toml | Skip dependency install |

## Common Mistakes

### Letting the harness pick the location

- **Problem:** Calling `EnterWorktree(name=…)` (or any native tool's create
  mode) because it is one call and it works. It does work — into
  `.claude/worktrees/`, while the Copilot sessions on the same repository go to
  the cache and the editor goes to `.worktrees/`. Nothing errors; the worktrees
  simply stop being in one place, and only `git worktree list` can still find
  them all.
- **Fix:** Choose the location in Step 1a, create it in Step 1b, and use the
  native tool in Step 1c with `path` to enter what you already made.

### Creating a second worktree for work already isolated

- **Problem:** Using `git worktree add` when the platform already provides isolation
- **Fix:** Step 0 detects existing isolation and skips straight to Step 2.

### Skipping detection

- **Problem:** Creating a nested worktree inside an existing one
- **Fix:** Always run Step 0 before creating anything

### Skipping ignore verification

- **Problem:** Worktree contents get tracked, pollute git status
- **Fix:** Use `git check-ignore` before a project-local worktree; use the
  cache fallback when it is not already ignored

### Assuming directory location

- **Problem:** Creates inconsistency, violates project conventions
- **Fix:** Follow priority: qualifying explicit preference > ignored
  `.worktrees/` at the repository root > cache fallback

### Leaving cache worktrees behind

- **Problem:** Cache-hosted worktrees accumulate after merge or discard.
- **Fix:** Run the complete cleanup block from any same-repository checkout so
  it reconstructs and validates the exact cache path before removal, then
  prunes.

### Proceeding with failing tests

- **Problem:** Can't distinguish new bugs from pre-existing issues
- **Fix:** Report failures, get explicit permission to proceed

### Committing in a detached worktree

- **Problem:** Worktrees are frequently created detached (`git worktree list`
  shows `(detached HEAD)` — the most common state in this repo's session logs).
  Commits made there belong to no branch and are invisible to `git branch` and
  `git log <branch>`.
- **Fix:** `git -C "$WT" symbolic-ref -q HEAD || git -C "$WT" branch <name> HEAD`
  *before* any further checkout. See
  [git-troubleshooting](../git-troubleshooting/SKILL.md) for recovery when the
  commits are already unreferenced, and for `bad object` / `not a git
  repository` errors caused by running git against the wrong worktree.

## Red Flags

**Never:**
- Create a worktree when Step 0 detects existing isolation
- Let a native tool choose the location. `EnterWorktree(name=…)` is the #1
  mistake — it silently plants the worktree in `.claude/worktrees/` instead of
  the shared directory. Pass `path` to a worktree you already created.
- Skip Step 1a by jumping straight to Step 1b's git commands
- Create worktree without verifying it's ignored (project-local)
- Create or change repository ignore rules for worktree storage
- Leave a cache-hosted worktree after merge or discard
- Skip baseline test verification
- Proceed with failing tests without asking

**Always:**
- Run Step 0 detection first
- Use native tools to *enter* the worktree you created, never to place it
- Follow directory priority: explicit preference > ignored `.worktrees/` at the repository root > cache fallback
- Verify directory is ignored for project-local
- Remove cache-hosted worktrees for merge and discard choices
- Auto-detect and run project setup
- Verify clean test baseline
