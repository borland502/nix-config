---
name: git-worktrees
description: Use when starting feature work that needs isolation from current workspace or before executing implementation plans - ensures an isolated workspace exists via native tools or git worktree fallback
---

# Using Git Worktrees

## Overview

Ensure work happens in an isolated workspace. Prefer your platform's native worktree tools. Fall back to manual git worktrees only when no native tool is available.

**Core principle:** Detect existing isolation first. Then use native tools. Then fall back to git. Never fight the harness.

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

**You have two mechanisms. Try them in this order.**

### 1a. Native Worktree Tools (preferred)

The user has asked for an isolated workspace (Step 0 consent). Do you already have a way to create a worktree? It might be a tool with a name like `EnterWorktree`, `WorktreeCreate`, a `/worktree` command, or a `--worktree` flag. If you do, use it and skip to Step 2.

Native tools handle directory placement, branch creation, and cleanup automatically. Using `git worktree add` when you have a native tool creates phantom state your harness can't see or manage.

Only proceed to Step 1b if you have no native worktree tool available.

### 1b. Git Worktree Fallback

**Only use this if Step 1a does not apply** — you have no native worktree tool available. Create a worktree manually using git.

#### Directory Selection

Follow this priority order. Explicit user preference always beats observed filesystem state.

1. **Check your instructions for a declared worktree directory preference.**
   Use it unless it is repository-local and `git check-ignore -q` does not
   confirm it is already ignored. Reject an unignored repository-local
   preference; do not alter repository ignore rules.

2. **Check for an existing project-local worktree directory:**
   ```bash
   ls -d .worktrees 2>/dev/null     # Preferred (hidden)
   ls -d worktrees 2>/dev/null      # Alternative
   ```
   Use `.worktrees/` only when `git check-ignore -q .worktrees` succeeds;
   otherwise use `worktrees/` only when `git check-ignore -q worktrees`
   succeeds. If both qualify, `.worktrees/` wins.

3. **Otherwise, default outside the repository:**
   `${XDG_CACHE_HOME:-$HOME/.cache}/copilot/worktrees/<repository>-<root-hash>`.
   The creation block calculates the physical root and collision-safe cache
   location itself.

**Why critical:** A repository-local worktree must already be ignored to
prevent accidental tracking. Cache fallback preserves that safety without
modifying repository files.

#### Create the Worktree

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
  case "$PREFERRED_LOCATION/" in
    "$ROOT/"*)
      git check-ignore -q "$PREFERRED_LOCATION/" || {
        echo "Repository-local worktree path is not ignored: $PREFERRED_LOCATION" >&2
        exit 1
      }
      ;;
  esac
  LOCATION="$PREFERRED_LOCATION"
elif [[ -d "$ROOT/.worktrees" ]] &&
  git check-ignore -q "$ROOT/.worktrees/"; then
  LOCATION="$ROOT/.worktrees"
elif [[ -d "$ROOT/worktrees" ]] &&
  git check-ignore -q "$ROOT/worktrees/"; then
  LOCATION="$ROOT/worktrees"
else
  REPOSITORY=$(printf '%s' "$(basename "$ROOT")" |
    LC_ALL=C tr -cs '[:alnum:]._-' '-' | cut -c1-80)
  ROOT_HASH=$(printf '%s' "$ROOT" | git hash-object --stdin)
  LOCATION="${XDG_CACHE_HOME:-$HOME/.cache}/copilot/worktrees/${REPOSITORY}-${ROOT_HASH}"
fi

WORKTREE_PATH="$LOCATION/$BRANCH_NAME"
mkdir -p "$LOCATION"
git worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME"
WORKTREE_PATH=$(cd "$WORKTREE_PATH" && pwd -P)
printf 'WORKTREE_PATH=%s\n' "$WORKTREE_PATH"
```

Use that printed absolute path explicitly as the working directory for every
later shell call. A terminal `cd` does not persist across tool invocations.

#### Cleanup

The workflow owns cache-hosted worktrees under
`${XDG_CACHE_HOME:-$HOME/.cache}/copilot/worktrees/`; they are removed for
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
EXPECTED_PARENT="${XDG_CACHE_HOME:-$HOME/.cache}/copilot/worktrees/${REPOSITORY}-${ROOT_HASH}"
EXPECTED_PARENT=$(cd "$EXPECTED_PARENT" && pwd -P)
WORKTREE_PATH="$EXPECTED_PARENT/$BRANCH_NAME"
WORKTREE_PATH=$(cd "$WORKTREE_PATH" && pwd -P)
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

This recomputes the root-hash/branch path and verifies its Git common directory
and branch instead of relying on variables from the creation turn. Do not
remove sibling cache worktrees.

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
| Native worktree tool available | Use it (Step 1a) |
| No native tool | Git worktree fallback (Step 1b) |
| Explicit directory preference | Use it only if repository-local path is already ignored |
| `.worktrees/` exists | Use it only if already ignored |
| `worktrees/` exists | Use it only if already ignored |
| Both existing directories qualify | Use `.worktrees/` |
| No qualifying local directory | Use `${XDG_CACHE_HOME:-$HOME/.cache}/copilot/worktrees/<repository>-<root-hash>`, then append branch once |
| Directory not ignored | Reject repository-local path; use cache fallback |
| Merge or discard cache worktree | Recompute and validate its root-hash/branch path, remove it, then prune |
| Permission error on create | Sandbox fallback, work in place |
| Tests fail during baseline | Report failures + ask |
| No package.json/Cargo.toml | Skip dependency install |

## Common Mistakes

### Fighting the harness

- **Problem:** Using `git worktree add` when the platform already provides isolation
- **Fix:** Step 0 detects existing isolation. Step 1a defers to native tools.

### Skipping detection

- **Problem:** Creating a nested worktree inside an existing one
- **Fix:** Always run Step 0 before creating anything

### Skipping ignore verification

- **Problem:** Worktree contents get tracked, pollute git status
- **Fix:** Use `git check-ignore` before a project-local worktree; use the
  cache fallback when it is not already ignored

### Assuming directory location

- **Problem:** Creates inconsistency, violates project conventions
- **Fix:** Follow priority: qualifying explicit preference > qualifying
  existing project-local directory > cache fallback

### Leaving cache worktrees behind

- **Problem:** Cache-hosted worktrees accumulate after merge or discard.
- **Fix:** Run the complete cleanup block from any same-repository checkout so
  it reconstructs and validates the exact cache path before removal, then
  prunes.

### Proceeding with failing tests

- **Problem:** Can't distinguish new bugs from pre-existing issues
- **Fix:** Report failures, get explicit permission to proceed

## Red Flags

**Never:**
- Create a worktree when Step 0 detects existing isolation
- Use `git worktree add` when you have a native worktree tool (e.g., `EnterWorktree`). This is the #1 mistake — if you have it, use it.
- Skip Step 1a by jumping straight to Step 1b's git commands
- Create worktree without verifying it's ignored (project-local)
- Create or change repository ignore rules for worktree storage
- Leave a cache-hosted worktree after merge or discard
- Skip baseline test verification
- Proceed with failing tests without asking

**Always:**
- Run Step 0 detection first
- Prefer native tools over git fallback
- Follow directory priority: explicit preference > existing ignored local directory > cache fallback
- Verify directory is ignored for project-local
- Remove cache-hosted worktrees for merge and discard choices
- Auto-detect and run project setup
- Verify clean test baseline
