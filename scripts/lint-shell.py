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


ALLOWLIST = Path('scripts/bash-allowlist.txt')


def load_allowlist(root):
    """Repo-relative paths still allowed to use bash; '#' starts a comment."""
    path = root / ALLOWLIST
    if not path.is_file():
        return set()
    entries = set()
    for line in path.read_text().splitlines():
        entry = line.split('#', 1)[0].strip()
        if entry:
            entries.add(entry)
    return entries


def bash_violations(scripts, allowlist):
    return sorted(name for name, shell in scripts.items() if shell == 'bash' and name not in allowlist)


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
    for name in bash_violations(scripts, load_allowlist(args.root)):
        print(f'{name}: bash outside {ALLOWLIST}; write zsh (floor 5.9) instead', file=sys.stderr)
        failed = True
    for name, shell in scripts.items():
        if shell == 'zsh':
            commands = [['zsh', '-f', '-n', name]]
            if args.format and not name.startswith('ai-tools/'):
                commands.append(['shfmt', '-d', '-i', '0', '-ln', 'zsh', name])
        else:
            dialect = 'sh' if shell == 'dash' else shell
            commands = [['shellcheck', '-x', '--shell', dialect, name]]
            # Preserve the established formatting exemption for imported skills;
            # syntax and ShellCheck still cover their shell sources.
            if args.format and shell != 'ksh' and not name.startswith('ai-tools/'):
                commands.append(['shfmt', '-d', '-i', '0', name])
        for command in commands:
            failed |= subprocess.run(command, cwd=args.root, check=False).returncode != 0
    print(f'Checked {len(scripts)} shell sources (zsh: syntax + shfmt; bash limited to {ALLOWLIST}).')
    return int(failed)


if __name__ == '__main__':
    sys.exit(main())
