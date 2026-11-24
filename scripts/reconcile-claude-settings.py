#!/usr/bin/env python3
"""Reconcile managed Claude settings without replacing user-owned hooks."""

import copy
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import sys

library = os.environ.get("AGENT_TOOLS_LIB")
sys.path.insert(
    0, library or str(Path(__file__).resolve().parents[1] / "chezmoi/dot_local/lib")
)
from agent_tools.artifacts import atomic_output  # noqa: E402

merger_path = os.environ.get(
    "AGENT_CAPTURE_MERGER",
    str(Path(__file__).with_name("merge-agent-capture-hooks.py")),
)
spec = importlib.util.spec_from_file_location("capture_merger", merger_path)
merger = importlib.util.module_from_spec(spec)
spec.loader.exec_module(merger)


def reconcile(data, manifest):
    merger.validate(data)
    merger.validate(manifest)

    def rewrite(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if key == "command" and isinstance(item, str):
                    value[key] = re.sub(
                        r"/\.local/bin/(log-bash\.sh|log-thinking\.sh|compress-old-cache|claude-cache-stats|aws-mcp-server)",
                        r"/.local/bin/ai-tools/\1",
                        item,
                    )
                else:
                    rewrite(item)
        elif isinstance(value, list):
            for item in value:
                rewrite(item)

    rewrite(data)
    hooks = data.setdefault("hooks", {})
    for event in ("Stop", "SubagentStop"):
        if event in hooks:
            groups = []
            for group in hooks[event]:
                kept = [
                    h
                    for h in group["hooks"]
                    if "log-thinking" not in h.get("command", "")
                ]
                if kept:
                    groups.append({**group, "hooks": kept})
            if groups:
                hooks[event] = groups
            else:
                del hooks[event]
    for group in hooks.get("Stop", []):
        for hook in group["hooks"]:
            if "compress-old-cache" in hook.get("command", ""):
                hook["async"] = True
    managed = [
        (
            "PostToolUse",
            "Bash",
            "log-bash.sh",
            'AGENT_NAME=claude bash "$HOME/.local/bin/ai-tools/log-bash.sh"',
            {"async": True},
        ),
        (
            "PostToolUse",
            "Skill",
            "log-skill.sh",
            'AGENT_NAME=claude bash "$HOME/.local/bin/ai-tools/log-skill.sh"',
            {"async": True},
        ),
        (
            "InstructionsLoaded",
            None,
            "log-instructions",
            'AGENT_NAME=claude bash "$HOME/.local/bin/ai-tools/log-instructions.sh"',
            {"async": True},
        ),
        (
            "SessionEnd",
            None,
            "claude-cache-stats",
            "$HOME/.local/bin/ai-tools/claude-cache-stats",
            {"async": True},
        ),
        (
            "PreToolUse",
            "Bash",
            "bash-habits-hint",
            '"$HOME/.local/bin/ai-tools/bash-habits-hint"',
            {"timeout": 5},
        ),
        (
            "PostToolUse",
            "Edit|Write|MultiEdit",
            "format-on-edit",
            '"$HOME/.local/bin/ai-tools/format-on-edit"',
            {"timeout": 30},
        ),
    ]

    def managed_handler(handler, command):
        try:
            expected = next(
                word
                for word in shlex.split(command)
                if word.startswith("$HOME/.local/bin/ai-tools/")
            )
            words = shlex.split(handler.get("command", ""))
        except (ValueError, TypeError, StopIteration):
            return False
        def assignment(word):
            return re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", word) is not None

        while words and assignment(words[0]):
            words.pop(0)
        if words and Path(words[0]).name == "env":
            words.pop(0)
            while words and assignment(words[0]):
                words.pop(0)
        if words and Path(words[0]).name in ("bash", "sh", "zsh"):
            words.pop(0)
            if words and words[0] == "--":
                words.pop(0)
        return bool(words) and words[0] in (
            expected,
            str(Path.home()) + expected[len("$HOME") :],
        )

    for event, matcher, marker, command, options in managed:
        if not any(
            g.get("matcher") == matcher and managed_handler(h, command)
            for g in hooks.get(event, [])
            for h in g["hooks"]
        ):
            group = {"hooks": [{"type": "command", "command": command, **options}]}
            if matcher is not None:
                group["matcher"] = matcher
            hooks.setdefault(event, []).append(group)
    merger.merge(data, manifest)
    if data.get("attribution") is None or data.get("attribution") is False:
        data["attribution"] = {"commit": "", "pr": ""}
    data["skillListingBudgetFraction"] = 0.03
    env = data.get("env")
    if env is not None:
        if not isinstance(env, dict):
            raise ValueError("env must be an object")
        for tier in ("OPUS", "SONNET", "HAIKU"):
            env.pop(f"ANTHROPIC_DEFAULT_{tier}_MODEL", None)
        if not env:
            del data["env"]
    model = data.get("model") or ""
    if not isinstance(model, str):
        raise ValueError("model must be a string")
    if not model or model.startswith("claude-"):
        data["model"] = "opus"
    return data


def main():
    target, manifest = map(Path, sys.argv[1:])
    if target.is_symlink():
        raise ValueError("refusing symlinked settings")
    existed = target.exists()
    original = target.read_bytes() if existed else b"{}"
    parsed = json.loads(original)
    result = reconcile(copy.deepcopy(parsed), json.loads(manifest.read_text()))
    if existed and result == parsed:
        target.chmod(0o600)
        return
    encoded = (json.dumps(result, indent=2) + "\n").encode()
    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)

    def check_concurrent_edit():
        if (
            target.is_symlink()
            or target.exists() != existed
            or (existed and target.read_bytes() != original)
        ):
            raise ValueError("settings changed during reconciliation; retry")

    with atomic_output(
        target, replace=True, before_publish=check_concurrent_edit
    ) as output:
        output.write(encoded)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, TypeError) as error:
        print(f"reconcile-claude-settings: {error}", file=sys.stderr)
        sys.exit(1)
