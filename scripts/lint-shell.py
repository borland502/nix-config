#!/usr/bin/env python3
"""Lint repository shell sources by shebang, including extensionless chezmoi files."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'chezmoi/dot_local/lib'))
from agent_tools.sources import shell_sources  # noqa: E402


def discover(root):
    return shell_sources(root)


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
            commands = [['shellcheck', '-x', '--shell', dialect, name]]
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
