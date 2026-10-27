#!/usr/bin/env python3
"""Lint repository shell sources by shebang, including extensionless chezmoi files."""
import argparse
import json
from pathlib import Path
import shlex
import subprocess
import sys

EXCLUDED = {'.git', '.worktrees', 'node_modules', 'vendor', '.venv', 'venv', 'secrets'}


def discover(root):
    result = subprocess.run(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'],
                            cwd=root, check=True, capture_output=True)
    scripts = {}
    for name in sorted(set(result.stdout.decode().split('\0')) - {''}):
        path = root / name
        if EXCLUDED.intersection(path.relative_to(root).parts) or path.suffix == '.tmpl':
            continue
        if path.is_symlink() or not path.is_file():
            continue
        with path.open('rb') as stream:
            first = stream.readline(512).decode('utf-8', errors='replace').strip()
        if not first.startswith('#!'):
            continue
        words = shlex.split(first[2:])
        if not words:
            continue
        interpreter = Path(words[0]).name
        if interpreter == 'env':
            words = [word for word in words[1:] if not word.startswith('-') and '=' not in word]
            interpreter = words[0] if words else ''
        if interpreter in {'bash', 'sh', 'dash', 'ksh', 'zsh'}:
            scripts[name] = interpreter
    return scripts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--list', action='store_true', help='print filename-to-shell mapping as JSON')
    parser.add_argument('--format', action='store_true', help='also check shfmt for supported dialects')
    args = parser.parse_args()
    scripts = discover(args.root)
    if args.list:
        print(json.dumps(scripts, indent=2))
        return 0
    failed = False
    for name, shell in scripts.items():
        if shell == 'zsh':
            commands = [['zsh', '-f', '-n', name]]
        else:
            dialect = 'sh' if shell == 'dash' else shell
            commands = [['shellcheck', '--shell', dialect, name]]
            # Preserve the established formatting exemption for imported skills;
            # syntax and ShellCheck still cover their shell sources.
            if args.format and shell != 'ksh' and not name.startswith('ai-tools/'):
                commands.append(['shfmt', '-d', '-i', '0', name])
        for command in commands:
            failed |= subprocess.run(command, cwd=args.root, check=False).returncode != 0
    print(f'Checked {len(scripts)} shell sources (zsh uses syntax checking).')
    return int(failed)


if __name__ == '__main__':
    sys.exit(main())
