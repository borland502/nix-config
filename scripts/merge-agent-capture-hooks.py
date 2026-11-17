#!/usr/bin/env python3
"""Configure passive capture and seed Codex defaults, preserving other settings."""
import json
import os
from pathlib import Path
import shlex
import sys
import tomllib

_library = os.environ.get("AGENT_TOOLS_LIB")
if _library:
    sys.path.insert(0, _library)
else:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "chezmoi/dot_local/lib"))
from agent_tools.artifacts import atomic_output  # noqa: E402


def owned(hook):
    command = hook.get("command", "")
    try:
        words = shlex.split(command)
    except ValueError:
        return False
    return any(word in {
        f"$HOME/.local/bin/ai-tools/{name}",
        str(Path.home() / ".local/bin/ai-tools" / name),
    } for word in words for name in ("agent-cache-capture", "sweep-agent-assets"))


def validate(data):
    if not isinstance(data, dict) or not isinstance(data.get("hooks", {}), dict):
        raise ValueError("settings and hooks must be JSON objects")
    for groups in data.get("hooks", {}).values():
        if not isinstance(groups, list):
            raise ValueError("hook event must contain a list")
        for group in groups:
            if not isinstance(group, dict) or not isinstance(group.get("hooks"), list):
                raise ValueError("hook group must contain a hooks list")
            if any(not isinstance(hook, dict) for hook in group["hooks"]):
                raise ValueError("hook handlers must be objects")


def merge(settings, additions):
    validate(settings)
    validate(additions)
    hooks = settings.setdefault("hooks", {})
    for event, groups in list(hooks.items()):
        remaining = []
        for group in groups:
            kept = [hook for hook in group["hooks"] if not owned(hook)]
            if kept:
                remaining.append({**group, "hooks": kept})
        if remaining:
            hooks[event] = remaining
        else:
            del hooks[event]
    for event, groups in additions["hooks"].items():
        hooks.setdefault(event, []).extend(groups)
    return settings


# Codex's "Approve for me" permissions preset (auto-review): the reviewer, not
# the user, answers escalation requests and only asks about actions it flags
# as potentially unsafe.
CODEX_APPROVE_FOR_ME = {
    "approvals_reviewer": "auto_review",
    "approval_policy": "on-request",
    "sandbox_mode": "workspace-write",
}
# Any of these means permissions were already chosen; seed none of the preset
# rather than mix it with an explicit choice.
CODEX_PERMISSION_KEYS = (*CODEX_APPROVE_FOR_ME, "default_permissions")


def seed_toml(original, values, guard_keys):
    """Prefix top-level keys unless a guard key is set; None means leave as is.

    Prefixing validated top-level keys preserves comments, table scopes,
    multiline strings and every existing setting without a TOML rewrite.
    """
    config = tomllib.loads(original.decode())
    if any(key in config for key in guard_keys):
        return None
    encoded = "".join(f"{key} = {json.dumps(value)}\n" for key, value in values.items()).encode() + original
    tomllib.loads(encoded.decode())
    return encoded


def main():
    mode = sys.argv[1] if sys.argv[1:2] in (["--codex-log-dir"], ["--codex-approve-for-me"]) else None
    if mode == "--codex-approve-for-me":
        (target,) = map(Path, sys.argv[2:])
    else:
        target, source = map(Path, sys.argv[2:] if mode else sys.argv[1:])
    if target.is_symlink():
        raise ValueError("refusing to replace symlinked settings")
    original = target.read_bytes() if target.exists() else (b"" if mode else b"{}")
    if mode:
        if mode == "--codex-log-dir":
            encoded = seed_toml(original, {"log_dir": str(source)}, ("log_dir",))
        else:
            encoded = seed_toml(original, CODEX_APPROVE_FOR_ME, CODEX_PERMISSION_KEYS)
        if encoded is None:
            return
    else:
        result = merge(json.loads(original), json.loads(source.read_text()))
        encoded = (json.dumps(result, indent=2) + "\n").encode()
    if encoded == original:
        target.chmod(0o600)
        return
    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    def check_concurrent_edit():
        # Do not clobber a concurrent settings edit made during generation.
        if target.exists() and target.read_bytes() != original:
            raise ValueError("settings changed during capture hook merge; retry")

    with atomic_output(target, replace=True, before_publish=check_concurrent_edit) as out:
        out.write(encoded)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, TypeError) as error:
        print(f"merge-agent-capture-hooks: {error}", file=sys.stderr)
        sys.exit(1)
