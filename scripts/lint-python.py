#!/usr/bin/env python3
"""Discover Python files and shebang programs; retain established Ruff coverage."""

import argparse
import json
from pathlib import Path
import re
import subprocess

EXCLUDED = {".git", ".worktrees", "node_modules", "vendor", ".venv", "venv", "secrets"}


def discover(root):
    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=root,
        check=True,
        capture_output=True,
    )
    files = []
    for name in sorted(set(result.stdout.decode().split("\0")) - {""}):
        path = root / name
        if (
            EXCLUDED.intersection(Path(name).parts)
            or path.is_symlink()
            or not path.is_file()
            or path.suffix == ".tmpl"
        ):
            continue
        with path.open("rb") as stream:
            first = stream.readline(512).decode("utf-8", errors="replace")
        if path.suffix == ".py" or (
            first.startswith("#!")
            and re.search(r"(?:^|[/\s])python(?:3(?:\.\d+)?)?(?:\s|$)", first)
        ):
            files.append(name)
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root", type=Path, default=Path(__file__).resolve().parents[1]
    )
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()
    files = discover(args.root)
    if args.list:
        print(json.dumps(files, indent=2))
        return 0
    # Preserve all previously enabled rules for conventional first-party .py.
    old = subprocess.run(
        ["ruff", "check", "--exclude", "ai-tools,secrets", "."],
        cwd=args.root,
        check=False,
    )
    # Correctness coverage for all discovered sources, including extensionless tools.
    new = (
        subprocess.run(
            ["ruff", "check", "--select", "E9,F63,F7,F82", "--", *files],
            cwd=args.root,
            check=False,
        )
        if files
        else None
    )
    print(f"Checked {len(files)} Python sources.")
    return int(old.returncode != 0 or (new is not None and new.returncode != 0))


if __name__ == "__main__":
    raise SystemExit(main())
