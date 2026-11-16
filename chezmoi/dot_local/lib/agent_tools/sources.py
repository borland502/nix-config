"""Discover first-party Python and shell sources in a Git checkout."""

from pathlib import Path
import re
import shlex
import subprocess

EXCLUDED = {".git", ".worktrees", "node_modules", "vendor", ".venv", "venv", "secrets"}
SHELLS = {"bash", "sh", "dash", "ksh", "zsh"}


def _sources(root):
    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=root, check=True, capture_output=True,
    )
    for name in sorted(set(result.stdout.decode().split("\0")) - {""}):
        path = root / name
        if (EXCLUDED.intersection(Path(name).parts) or path.suffix == ".tmpl"
                or path.is_symlink() or not path.is_file()):
            continue
        with path.open("rb") as stream:
            first = stream.readline(512).decode("utf-8", errors="replace")
        yield name, path, first


def python_sources(root: Path) -> list[str]:
    return [name for name, path, first in _sources(root) if path.suffix == ".py" or (
        first.startswith("#!")
        and re.search(r"(?:^|[/\s])python(?:3(?:\.\d+)?)?(?:\s|$)", first)
    )]


def shell_sources(root: Path) -> dict[str, str]:
    scripts = {}
    for name, _, first in _sources(root):
        first = first.strip()
        declaration = re.fullmatch(r"#\s*shellcheck\s+shell=(bash|sh|dash|ksh|zsh)\s*", first)
        if declaration:
            scripts[name] = declaration.group(1)
            continue
        if not first.startswith("#!"):
            continue
        words = shlex.split(first[2:])
        if not words:
            continue
        interpreter = Path(words[0]).name
        if interpreter == "env":
            words = [word for word in words[1:] if not word.startswith("-") and "=" not in word]
            interpreter = words[0] if words else ""
        if interpreter in SHELLS:
            scripts[name] = interpreter
    return scripts
