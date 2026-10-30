---
name: git-worktrees
description: Use when starting feature work that needs isolation from current workspace or before executing implementation plans - ensures an isolated workspace exists in the one shared worktree location every harness and the editor agree on
---

# Using git worktrees

Ensure isolation in the shared location used by all harnesses and the editor.
Detect existing isolation first, choose the location, create with git, then bind
the session. Announce use of this skill. An inventory-only request uses
`git-worktree-audit [REPO] [--base REF ...]` and makes no changes.

## Detect before creating

Resolve physical paths for `git rev-parse --show-toplevel`, `--git-dir` and
`--git-common-dir`, plus `git branch --show-current`. Check
`git rev-parse --show-superproject-working-tree`: a submodule also has differing
git directories and must not be mistaken for a linked worktree.

When git dir differs from common dir and this is not a submodule, reuse the
existing linked worktree and report its path and branch. Do not create nested
isolation. For externally managed detached HEAD, report that state; ensure a
named branch references any new commits before leaving it. Do not switch away
and strand commits. Use [git-troubleshooting](../git-troubleshooting/SKILL.md)
for recovery or invalid repository/revision evidence.

In a normal checkout, honor the user's declared preference and existing
authorization. Ask about isolation only when no preference or authorization
exists; if declined, work in place. Do not re-ask just because the design was
approved in an earlier turn.

## Choose and create only when needed

Read [creation and binding](references/creation-and-binding.md) before creating;
it contains the complete atomic creation block and native-tool constraints.
Use this priority:

1. Explicit user location. A repository-local choice must already be ignored.
2. Root `.worktrees/` when `git check-ignore -q` confirms it is ignored; create
   it if absent. Do not require it to pre-exist.
3. Existing root `worktrees/` only when already ignored.
4. `${XDG_CACHE_HOME:-$HOME/.cache}/git-worktrees/REPOSITORY-ROOT_HASH`, a physical
   root keyed by the repository's full git object hash, then the branch once.

Reject unignored repository-local locations; never add ignore rules for agent
storage. Reject existing or redirected destination paths, and validate physical
cache parents before `git worktree add`. Choose the location before using a
harness tool. Native tools may enter the created path but must not pick their
own location. In Claude, use `EnterWorktree(path=...)`, never `name=...`; the
latter creates a separate harness-specific tree. Tools without binding simply
use the printed absolute path for every subsequent command.

If creation is denied by the sandbox, explain the denial and work in place
under the existing scope when safe. Do not repeatedly retry an unavailable
mutation or conceal a blocker requiring permission.

## Set up and verify

Check root and ancestors for an allowed `.envrc`; run project commands through
`direnv exec ROOT COMMAND`. A login shell does not substitute for this.
Inspect repository instructions and declared workflows; use their setup and
baseline checks appropriate to the change. Do not blindly install dependencies
when the existing project environment is sufficient. Preserve unrelated dirty
files and report pre-existing failures separately so new regressions remain
identifiable. Existing user authorization to investigate or fix a failure
persists; ask only if a genuinely new scope or consequential decision blocks
safe progress.

Report the worktree path/branch, baseline command and actual result. A dirty
working tree is not itself a failed test or permission to reset user changes.

## Cleanup is a separate authorized action

Read [guarded cleanup](references/guarded-cleanup.md) only after the user chooses
merge or discard and cleanup is authorized. Reconstruct the exact cache path,
reject symlink redirection, verify its common git directory and expected branch,
then remove only that worktree and prune. Discard is destructive and requires
that actual choice. Never remove siblings, merge without explicit instruction,
or treat session binding as ownership of a shared worktree. Claude exits a
path-entered worktree with `action: "keep"`; the guarded cleanup owns removal.
