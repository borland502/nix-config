"""Configured source roots shared by the scanner and copy-only collector."""

import os
from pathlib import Path


def unique_homes(configured, defaults):
    result, seen = [], set()
    for candidate in ([Path(configured)] if configured else []) + list(defaults):
        try:
            resolved = candidate.expanduser().resolve(strict=True)
        except OSError:
            continue
        if resolved.is_dir() and resolved not in seen:
            seen.add(resolved)
            result.append(resolved)
    return result


def agent_homes(agent, home=None):
    home = Path.home() if home is None else home
    config = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
    variable = {
        "codex": "CODEX_HOME",
        "claude": "CLAUDE_CONFIG_DIR",
        "copilot": "COPILOT_HOME",
    }[agent]
    return unique_homes(
        os.environ.get(variable), (config / agent, home / ("." + agent))
    )


def capture_root(home=None):
    home = Path.home() if home is None else home
    override = os.environ.get("AGENT_CACHE_CAPTURE_ROOT")
    base = Path(
        os.environ.get(
            "CACHE_DIR",
            Path(os.environ.get("XDG_CACHE_HOME", home / ".cache")) / "copilot",
        )
    )
    return (
        (Path(override) if override else base / "agent-capture")
        .expanduser()
        .resolve(strict=False)
    )


def log_roots(home=None):
    home = Path.home() if home is None else home
    cache = Path(os.environ.get("XDG_CACHE_HOME", home / ".cache"))
    candidates = [cache / name for name in ("claude", "copilot", "codex")]
    if os.environ.get("CACHE_DIR"):
        candidates.insert(0, Path(os.environ["CACHE_DIR"]))
    return unique_homes(None, candidates)
