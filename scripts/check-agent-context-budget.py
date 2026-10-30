#!/usr/bin/env python3
"""Inventory global agent entry points; fail size growth and broken local references."""

import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SKILL_BUDGET = 5000


def inventory(root):
    allowance_path = root / "scripts/agent-context-grandfather.json"
    allowances = (
        json.loads(allowance_path.read_text()) if allowance_path.exists() else {}
    )
    entries = sorted((root / "ai-tools/skills").glob("*/SKILL.md")) + sorted(
        (root / "ai-tools/agents").glob("*.md")
    )
    defaults = root / "chezmoi/dot_config/instructions/agent-defaults.md"
    if defaults.exists():
        entries.append(defaults)
    errors, rows, hashes = [], [], {}
    duplicates = []
    paragraphs = {}
    for entry in entries:
        name = str(entry.relative_to(root))
        content = entry.read_bytes()
        digest = hashlib.sha256(content).hexdigest()
        budget = 10000 if entry == defaults else SKILL_BUDGET
        grandfathered = allowances.get(name, {}).get("sha256") == digest
        if len(content) > budget and not grandfathered:
            errors.append(f"{name}: {len(content)} bytes exceeds budget {budget}")
        rows.append(
            {
                "path": name,
                "bytes": len(content),
                "budget": budget,
                "grandfathered": grandfathered,
            }
        )
        if digest in hashes:
            duplicates.append([hashes[digest], name])
        hashes[digest] = name
        for paragraph in content.decode().split("\n\n"):
            normalized = " ".join(paragraph.split())
            if len(normalized) >= 150:
                paragraphs.setdefault(normalized, set()).add(name)
        for target in re.findall(r"\[[^\]]*\]\(([^\s)]+)\)", content.decode()):
            if target.startswith(("http:", "https:", "#", "/", "~", "$", "skill:")):
                continue
            target = target.split("#", 1)[0]
            # Relative resource paths are statically checkable; command examples are not.
            if target and not (entry.parent / target).exists():
                errors.append(f"{name}: missing local reference {target}")
    reference = root / "chezmoi/dot_config/instructions/agent-reference.md"
    index = reference.read_text() if reference.exists() else ""
    helpers = ["agent-context", "cache-scan", "ops-agent", "jira-get", "confluence-get"]
    missing = [name for name in helpers if name not in index]
    if missing:
        errors.append("helper index missing: " + ", ".join(missing))
    return {
        "duplicate_paragraphs": [
            sorted(names) for names in paragraphs.values() if len(names) > 1
        ],
        "entries": rows,
        "duplicate_entries": duplicates,
        "missing_helpers": missing,
        "errors": errors,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--json", action="store_true")
    parser.add_argument(
        "--report-only", action="store_true", help="inventory without enforcing errors"
    )
    args = parser.parse_args()
    report = inventory(args.root)
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        for row in report["entries"]:
            print(
                f"{row['bytes']:6} / {row['budget']:5} {row['path']}"
                + (" (unchanged grandfathered entry)" if row["grandfathered"] else "")
            )
        for names in report["duplicate_paragraphs"]:
            print("shared paragraph signal: " + ", ".join(names))
        for pair in report["duplicate_entries"]:
            print("duplication signal: " + " = ".join(pair))
        for error in report["errors"]:
            print(error)
    return int(bool(report["errors"]) and not args.report_only)


if __name__ == "__main__":
    raise SystemExit(main())
