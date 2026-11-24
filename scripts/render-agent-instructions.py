#!/usr/bin/env python3
"""Render the same instruction bytes for Nix and committed dotfile deployment."""

import argparse
import difflib
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]


def render(source, manifest, name):
    target = manifest["targets"][name]
    body = source.replace("@@AGENT@@", target["agent"])
    if not target["frontmatter"]:
        return body.encode("utf-8")
    fields = (
        f"{key}: {json.dumps(value.format(agent=target['agent']), ensure_ascii=False)}\n"
        for key, value in manifest["frontmatter"].items()
    )
    return ("---\n" + "".join(fields) + "---\n\n" + body).encode("utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=Path,
        default=ROOT / "chezmoi/dot_config/instructions/agent-defaults.md",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=ROOT / "home-manager/lib/agent-instruction-targets.json",
    )
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("render").add_argument("target")
    for command in ("write", "check"):
        commands.add_parser(command).add_argument("output_root", type=Path)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    source = args.source.read_bytes().decode("utf-8")
    if args.command == "render":
        if args.target not in manifest["targets"]:
            parser.error(f"unknown instruction target: {args.target}")
        sys.stdout.buffer.write(render(source, manifest, args.target))
        return 0

    outputs = []
    for name, target in manifest["targets"].items():
        content = render(source, manifest, name)
        for destination in target["destinations"]:
            relative = Path(destination)
            if relative.is_absolute() or ".." in relative.parts:
                parser.error(f"instruction destination must be relative: {destination}")
            outputs.append((args.output_root / relative, content))

    stale = False
    for destination, content in outputs:
        if args.command == "write":
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(content)
            continue
        actual = destination.read_bytes() if destination.exists() else None
        if actual != content:
            stale = True
            print(f"Stale or missing instruction file: {destination}", file=sys.stderr)
            if actual is not None:
                sys.stderr.writelines(
                    difflib.unified_diff(
                        actual.decode("utf-8", errors="replace").splitlines(
                            keepends=True
                        ),
                        content.decode("utf-8").splitlines(keepends=True),
                        fromfile=str(destination),
                        tofile="rendered source",
                    )
                )
    if stale:
        print("Run: task generate:agent-instructions", file=sys.stderr)
    return int(stale)


if __name__ == "__main__":
    raise SystemExit(main())
