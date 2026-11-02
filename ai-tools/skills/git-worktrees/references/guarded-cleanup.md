# Guarded cleanup

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
