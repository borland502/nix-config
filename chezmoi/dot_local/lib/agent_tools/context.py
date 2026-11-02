"""Read-only, bounded discovery of the current agent working context."""

import json
import os
from pathlib import Path
import shutil
import subprocess

HELPERS = (
    "agent-context",
    "cache-scan",
    "ops-agent",
    "jira-get",
    "confluence-get",
    "gh",
    "task",
    "direnv",
)
LIMIT = 100


def query(argv, cwd, env):
    try:
        result = subprocess.run(
            argv,
            cwd=cwd,
            env=env,
            capture_output=True,
            text=True,
            # Git filenames may contain arbitrary bytes. Escaping undecodable
            # bytes keeps JSON and strict UTF-8 human output safe and legible.
            errors="backslashreplace",
            timeout=5,
            check=False,
        )
        return result.stdout.rstrip("\n") if result.returncode == 0 else None
    except (OSError, subprocess.SubprocessError):
        return None


def collect(path, *, env=None):
    env = dict(os.environ if env is None else env)
    env["GIT_OPTIONAL_LOCKS"] = "0"
    env["GIT_TERMINAL_PROMPT"] = "0"
    cwd = Path(path).resolve()
    home = Path(env.get("HOME", str(Path.home())))
    git = shutil.which("git", path=env.get("PATH", ""))
    worktree = query([git, "rev-parse", "--show-toplevel"], cwd, env) if git else None
    worktrees = (
        query(
            [git, "worktree", "list", "--porcelain", "-z"], cwd, env
        )
        if worktree
        else None
    )
    # The first entry identifies the primary checkout for ordinary worktrees.
    # Git may instead report metadata for submodules/separate git dirs; accept
    # it only when its checkout marker belongs to this Git common directory.
    primary = (worktrees or "").split("\0\0", 1)[0].split("\0")
    repository = worktree
    if primary[0].startswith("worktree ") and "bare" not in primary:
        candidate = Path(primary[0][len("worktree "):]).resolve()
        if (candidate / ".git").exists():
            common_args = [
                git, "rev-parse", "--path-format=absolute", "--git-common-dir"
            ]
            common = query(common_args, cwd, env)
            candidate_common = query(common_args, candidate, env)
            if (
                common
                and candidate_common
                and Path(common).resolve() == Path(candidate_common).resolve()
            ):
                repository = str(candidate)
    branch = (
        query([git, "symbolic-ref", "--short", "HEAD"], cwd, env) if worktree else None
    )
    raw = (
        query(
            [git, "status", "--porcelain=v1", "-z", "--untracked-files=normal"],
            cwd,
            env,
        )
        if worktree
        else None
    )
    names = []
    records = iter((raw or "").split("\0"))
    for record in records:
        if not record:
            continue
        names.append(record[3:])
        if record[:1] in {"R", "C"} or record[1:2] in {"R", "C"}:
            next(records, None)
    ancestors = list(reversed(cwd.parents)) + [cwd]
    instructions = [
        str(base / name)
        for base in ancestors
        for name in ("AGENTS.md", "CLAUDE.md", ".github/copilot-instructions.md")
        if (base / name).is_file()
    ]
    state = (
        Path(env.get("XDG_STATE_HOME", str(home / ".local/state")))
        / "chezmoi/nix-config-dir"
    )
    try:
        source = str(Path(state.read_text().strip()[:4096]) / "chezmoi")
    except OSError:
        source = None
    direnv = shutil.which("direnv", path=env.get("PATH", ""))
    approval = "unavailable"
    if direnv:
        status = query([direnv, "status", "--json"], cwd, env)
        try:
            found = json.loads(status or "{}").get("state", {}).get("foundRC")
            approval = (
                "absent"
                if not found
                else {0: "allowed", 1: "denied", 2: "unknown"}.get(
                    found.get("allowed"), "unknown"
                )
            )
        except (ValueError, AttributeError, TypeError):
            approval = "unknown"
    return {
        "path": str(cwd),
        "repository": repository,
        "worktree": worktree,
        "branch": branch,
        "dirty_files": names[:LIMIT],
        "dirty_files_truncated": len(names) > LIMIT,
        "instruction_paths": instructions[:LIMIT],
        "instruction_paths_truncated": len(instructions) > LIMIT,
        "chezmoi_source": source,
        "direnv": {
            "approval": approval,
            "envrc": next(
                (
                    str(base / ".envrc")
                    for base in reversed(ancestors)
                    if (base / ".envrc").is_file()
                ),
                None,
            ),
        },
        "helpers": {
            name: shutil.which(name, path=env.get("PATH", "")) for name in HELPERS
        },
    }
