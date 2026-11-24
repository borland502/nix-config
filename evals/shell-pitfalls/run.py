#!/usr/bin/env python3
"""Prepare an isolated Skillgrade suite and launch the requested mode."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

source = Path(__file__).resolve().parent
root = source.parents[1]
cache = Path.home() / ".cache" / "codex" / "skillgrade"
cache.mkdir(parents=True, exist_ok=True)
mode, *args = sys.argv[1:]
with tempfile.TemporaryDirectory(prefix="suite-", dir=cache) as tmp:
    suite = Path(tmp) / "shell-pitfalls"
    shutil.copytree(source, suite)
    config = suite / "eval.yaml"
    text = config.read_text().replace("skill: ../../ai-tools/skills/shell-pitfalls", f"skill: {json.dumps(str(root / 'ai-tools/skills/shell-pitfalls'))}")
    if mode == "validate":
        text = text.replace("    solution: reference.sh", "      - src: reference.sh\n        dest: reference.sh\n    solution: reference.sh")
    config.write_text(text)
    flags = {"list": ["--list"], "validate": ["--validate"], "run": []}[mode]
    command = [os.environ.get("SKILLGRADE", "skillgrade"), *flags, f"--output={cache}", *args]
    raise SystemExit(subprocess.call(command, cwd=suite))
