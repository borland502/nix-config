#!/usr/bin/env python3
"""Seed managed MCP servers without replacing explicit client choices."""
import argparse
import copy
import json
import math
import os
import re
from pathlib import Path
import sys
import tomllib

sys.path.insert(0, os.environ.get(
    "AGENT_TOOLS_LIB", str(Path(__file__).resolve().parents[1] / "chezmoi/dot_local/lib"),
))
from agent_tools.artifacts import atomic_output  # noqa: E402


def validate_manifest(mode, value):
    if not isinstance(value, dict):
        raise ValueError("manifest must be an object")
    allowed = {"command": str, "args": list, "url": str, "startup_timeout_sec": (int, float), "tool_timeout_sec": (int, float), "enabled": bool}
    if mode == "claude":
        allowed = {"type": str, "command": str, "args": list, "url": str, "env": dict, "headers": dict}
    for name, definition in value.items():
        if not isinstance(name, str) or not name or not isinstance(definition, dict) or not definition:
            raise ValueError("invalid server definition")
        for key, field in definition.items():
            expected = allowed.get(key)
            if expected is None or not isinstance(field, expected) or (isinstance(field, bool) and expected is not bool):
                raise ValueError("invalid server field: " + str(key))
            if isinstance(field, list) and not all(isinstance(item, str) for item in field):
                raise ValueError("server arguments must be strings")
            if isinstance(field, dict) and not all(isinstance(k, str) and isinstance(v, str) for k, v in field.items()):
                raise ValueError("server mappings must contain strings")
            if isinstance(field, float) and not math.isfinite(field):
                raise ValueError("non-finite timeout")
    return value


def seed(mode, original, manifest):
    manifest = validate_manifest(mode, manifest)
    if mode == "claude":
        config = json.loads(original or b"{}")
        if not isinstance(config, dict) or not isinstance(config.get("mcpServers", {}), dict):
            raise ValueError("Claude config and mcpServers must be objects")
        servers = config.get("mcpServers", {})
        missing = {name: definition for name, definition in manifest.items() if name not in servers}
        if not missing:
            return None
        config.setdefault("mcpServers", {}).update(missing)
        return (json.dumps(config, indent=2) + "\n").encode()

    config = tomllib.loads(original.decode())
    servers = config.get("mcp_servers", {})
    if not isinstance(servers, dict):
        raise ValueError("Codex mcp_servers must be a table")
    missing = {name: definition for name, definition in manifest.items() if name not in servers}
    if not missing:
        return None
    addition = ""
    for name, definition in missing.items():
        addition += "\n[mcp_servers." + json.dumps(name, ensure_ascii=True) + "]\n"
        for key, field in definition.items():
            addition += json.dumps(key) + " = " + json.dumps(field, ensure_ascii=True) + "\n"
    encoded = original + addition.encode()
    try:
        tomllib.loads(encoded.decode())
        return encoded
    except tomllib.TOMLDecodeError:
        # Inline TOML tables cannot be extended by a later table declaration.
        # Verify each candidate semantically so strings and nested tables cannot
        # accidentally be mistaken for the root assignment.
        desired = copy.deepcopy(config)
        desired["mcp_servers"].update(missing)
        fields = []
        for name, definition in missing.items():
            pairs = [json.dumps(k) + " = " + json.dumps(v, ensure_ascii=True) for k, v in definition.items()]
            fields.append(json.dumps(name, ensure_ascii=True) + " = { " + ", ".join(pairs) + " }")
        text = original.decode()
        pattern = r"(?m)^[ \t]*(?:mcp_servers|\"mcp_servers\"|'mcp_servers')[ \t]*=[ \t]*\{"
        for match in re.finditer(pattern, text):
            for close in (m.start() for m in re.finditer(r"\}", text[match.end():])):
                index = match.end() + close
                for prefix in ("", ", "):
                    candidate = text[:index] + prefix + ", ".join(fields) + text[index:]
                    try:
                        if tomllib.loads(candidate) == desired:
                            return candidate.encode()
                    except tomllib.TOMLDecodeError:
                        pass
        raise ValueError("cannot safely update inline mcp_servers table")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("client", choices=("claude", "codex"))
    parser.add_argument("config", type=Path)
    parser.add_argument("manifest")
    args = parser.parse_args()
    target = args.config
    if target.is_symlink():
        raise ValueError("refusing to replace symlinked client config")
    existed = target.exists()
    original = target.read_bytes() if existed else b""
    encoded = seed(args.client, original, json.loads(Path(args.manifest).read_text()))
    if encoded is None:
        return
    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)

    def check_concurrent_edit():
        if target.is_symlink() or target.exists() != existed:
            raise ValueError("client config changed during setup; retry")
        if existed and target.read_bytes() != original:
            raise ValueError("client config changed during setup; retry")

    with atomic_output(target, replace=existed, before_publish=check_concurrent_edit) as output:
        output.write(encoded)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, TypeError) as error:
        print(f"configure-agent-mcp: {error}", file=sys.stderr)
        sys.exit(1)
