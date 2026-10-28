#!/usr/bin/env python3
"""Configure passive capture while preserving unrelated agent settings."""
import json
import os
from pathlib import Path
import shlex
import sys
import tempfile
import tomllib


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


def main():
    log_dir_mode = sys.argv[1:2] == ["--codex-log-dir"]
    target, source = map(Path, sys.argv[2:] if log_dir_mode else sys.argv[1:])
    if target.is_symlink():
        raise ValueError("refusing to replace symlinked settings")
    original = target.read_bytes() if target.exists() else (b"" if log_dir_mode else b"{}")
    if log_dir_mode:
        # Prefixing a validated top-level key preserves comments, table scopes,
        # multiline strings and every existing setting without a TOML rewrite.
        config = tomllib.loads(original.decode())
        if "log_dir" in config:
            return
        encoded = ("log_dir = " + json.dumps(str(source)) + "\n").encode() + original
        tomllib.loads(encoded.decode())
    else:
        result = merge(json.loads(original), json.loads(source.read_text()))
        encoded = (json.dumps(result, indent=2) + "\n").encode()
    if encoded == original:
        target.chmod(0o600)
        return
    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".capture-settings-", dir=target.parent)
    try:
        with os.fdopen(fd, "wb") as out:
            out.write(encoded)
            out.flush()
            os.fsync(out.fileno())
        # Do not clobber a concurrent settings edit made during generation.
        if target.exists() and target.read_bytes() != original:
            raise ValueError("settings changed during capture hook merge; retry")
        os.replace(temporary, target)
    finally:
        Path(temporary).unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, TypeError) as error:
        print(f"merge-agent-capture-hooks: {error}", file=sys.stderr)
        sys.exit(1)
