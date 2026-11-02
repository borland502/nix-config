"""Checked subprocess execution with bounded, argument-free diagnostics."""
import os
from pathlib import Path
import subprocess

class ProcessError(RuntimeError):
    """A command failed, could not start, or exceeded its deadline."""

def run(argv, *, timeout=60, env=None, stdout=None):
    try:
        result = subprocess.run(argv, stdout=stdout if stdout is not None else subprocess.PIPE,
                                stderr=subprocess.PIPE, text=stdout is None,
                                timeout=timeout, env=env)
    except (OSError, subprocess.TimeoutExpired) as exc:
        reason = "timed out" if isinstance(exc, subprocess.TimeoutExpired) else "could not start"
        raise ProcessError(f"command {reason}") from exc
    if result.returncode:
        detail = result.stderr or ""
        if isinstance(detail, bytes):
            detail = detail.decode("utf-8", "replace")
        raise ProcessError(f"command exited {result.returncode}: {detail[:2000]}")
    return result

def kac_env():
    """Refresh through the sourced KAC adapter, returning its exported environment."""
    kac = os.environ.get("KAC_PATH", str(Path.home() / ".local/bin/kac"))
    result = run(["bash", "-c", 'source "$1" ensure >&2 || exit 1; env -0', "agent-tools", kac])
    return dict(item.split("=", 1) for item in result.stdout.split("\0") if "=" in item)
