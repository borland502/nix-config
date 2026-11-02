# Step 1: Create Isolated Workspace

**Location is chosen first, on every harness. Then the worktree is created.
Then the session is bound to it.** Do these three sub-steps in order.

Every harness must land worktrees in the *same* directory, so a native tool
that also picks the location is used only for the binding in Step 1c — never to
place the directory. A harness-chosen location is what splits one repository's
worktrees across `.claude/worktrees/`, a per-harness cache, and the repo, until
no tool and no human can see them all in one place.

## 1a. Directory Selection

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

## 1b. Create the Worktree

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

## 1c. Bind the Session to It

The worktree now exists at the shared location. If your harness has a native
worktree tool, use it here — to **enter** the directory Step 1b just created,
never to create one of its own.

**Claude Code (`EnterWorktree`):** pass `path`, never `name`.

```text
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
