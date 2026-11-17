"""Checked subprocess execution with bounded, argument-free diagnostics."""
import json
import os
from pathlib import Path
import subprocess

class ProcessError(RuntimeError):
    """A command failed, could not start, or exceeded its deadline."""

class ProcessTimeout(ProcessError):
    """A command exceeded its deadline."""

def run(argv, *, timeout=60, env=None, stdout=None):
    try:
        result = subprocess.run(argv, stdout=stdout if stdout is not None else subprocess.PIPE,
                                stderr=subprocess.PIPE, text=stdout is None,
                                timeout=timeout, env=env)
    except subprocess.TimeoutExpired as exc:
        raise ProcessTimeout("command timed out") from exc
    except OSError as exc:
        raise ProcessError("command could not start") from exc
    if result.returncode:
        detail = result.stderr or ""
        if isinstance(detail, bytes):
            detail = detail.decode("utf-8", "replace")
        raise ProcessError(f"command exited {result.returncode}: {detail[:2000]}")
    return result

def run_json(argv, *, timeout=60, env=None):
    try:
        return json.loads(run(argv, timeout=timeout, env=env).stdout)
    except (ValueError, UnicodeError) as exc:
        raise ProcessError("command returned malformed JSON") from exc

def kac_env():
    """Refresh through the sourced KAC adapter, returning its exported environment."""
    kac = os.environ.get("KAC_PATH", str(Path.home() / ".local/bin/kac"))
    result = run(["bash", "-c", 'source "$1" ensure >&2 || exit 1; env -0', "agent-tools", kac])
    return dict(item.split("=", 1) for item in result.stdout.split("\0") if "=" in item)
