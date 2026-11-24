#!/usr/bin/env python3
"""Resolve capability tiers to the newest OpenAI-family model slugs.

home-manager/lib/model-tiers.nix names a model family per tier (sol, terra,
luna) and a floor slug. Codex keeps the live model catalog it fetched in
$CODEX_HOME/models_cache.json. The newest listed `gpt-<version>-<family>` wins,
never below the floor, so the tiers move to new generations without a repo
edit. Copilot and Codex share these slugs. Without a catalog (fresh host,
Linux), the floor is used.

Commands write only when content changes:
  resolve                      print {"high","mid","low"} as JSON
  copilot-settings FILE        set the Copilot session model to the high tier
  codex-config FILE            seed `model` (high) or float it within its family
  codex-profiles CODEX_HOME    write the managed mid/low profile files
  codex-agents SRC DEST        copy custom agents with floor slugs resolved
"""

import argparse
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import tomllib

SLUG = re.compile(r"^gpt-(?P<version>\d+(?:\.\d+)*)-(?P<family>[a-z]+)$")
TOP_MODEL = re.compile(r'^model[ \t]*=[ \t]*"[^"\n]*"', re.M)
TABLE = re.compile(r"^[ \t]*\[", re.M)
MANAGED = "# Managed by nix-config scripts/resolve-model-tiers.py; rewritten on every switch.\n"
MANIFEST = ".nix-config-managed"
PROFILE_EFFORT = {"mid": "medium", "low": "low"}


def parse(slug):
    match = SLUG.match(slug) if isinstance(slug, str) else None
    if not match:
        return None
    return tuple(int(part) for part in match["version"].split(".")), match["family"]


def load_catalog(path):
    try:
        data = json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return []
    models = data.get("models") if isinstance(data, dict) else None
    if not isinstance(models, list):
        return []
    return [m for m in models if isinstance(m, dict) and isinstance(m.get("slug"), str)]


def listed(catalog):
    return {m["slug"]: m for m in catalog if m.get("visibility", "list") != "hide"}


def upgrade_target(entry):
    upgrade = entry.get("upgrade")
    if isinstance(upgrade, str):
        return upgrade
    if isinstance(upgrade, dict):
        for key in ("model", "slug", "id"):
            if isinstance(upgrade.get(key), str):
                return upgrade[key]
    return None


def follow_upgrades(slug, models):
    seen = {slug}
    while slug in models:
        target = upgrade_target(models[slug])
        if not target or target in seen or target not in models:
            break
        current, candidate = parse(slug), parse(target)
        # Catalog hints must preserve the family and newest-version floor.
        if not current or not candidate or candidate[1] != current[1] or candidate[0] < current[0]:
            break
        seen.add(target)
        slug = target
    return slug


def newest_in_family(family, models, floors=()):
    candidates = [s for s in [*models, *floors] if (p := parse(s)) and p[1] == family]
    if not candidates:
        return None
    return follow_upgrades(max(candidates, key=lambda s: parse(s)[0]), models)


def resolve(tiers, catalog):
    models = listed(catalog)
    resolved = {}
    for tier, family in tiers["family"].items():
        floor = tiers["floor"][tier]
        resolved[tier] = newest_in_family(family, models, [floor]) or floor
    return resolved


def floor_lag(tiers, resolved):
    notes = []
    for tier, floor in tiers["floor"].items():
        have, want = parse(floor), parse(resolved[tier])
        if have and want and have[1] == want[1] and want[0] > have[0]:
            notes.append(f"resolve-model-tiers: {tier} floor {floor} is behind {resolved[tier]}; raise it in home-manager/lib/model-tiers.nix")
    return notes


def write_atomic(path, text, mode):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w") as out:
            out.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def refuse_symlink(path):
    if path.is_symlink():
        raise ValueError(f"refusing to replace symlinked {path}")


def copilot_settings(path, resolved):
    refuse_symlink(path)
    original = path.read_text() if path.exists() else ""
    data = json.loads(original) if original.strip() else {}
    if data.get("model") == resolved["high"]:
        return
    data["model"] = resolved["high"]
    write_atomic(path, json.dumps(data, indent=2) + "\n", 0o600)


def codex_config(path, tiers, catalog, resolved):
    refuse_symlink(path)
    original = path.read_text() if path.exists() else ""
    current = tomllib.loads(original).get("model")
    if current is None:
        wanted = resolved["high"]
        updated = f"model = {json.dumps(wanted)}\n" + original
    else:
        have = parse(current)
        if not have:
            return  # an alias or unversioned slug is a deliberate choice
        floors = [s for s in tiers["floor"].values() if (p := parse(s)) and p[1] == have[1]]
        wanted = newest_in_family(have[1], listed(catalog), floors)
        newer = parse(wanted)
        if wanted is None or wanted == current or (newer and newer[1] == have[1] and newer[0] <= have[0]):
            return
        head_end = m.start() if (m := TABLE.search(original)) else len(original)
        head, changed = TOP_MODEL.subn(f"model = {json.dumps(wanted)}", original[:head_end], count=1)
        if not changed:
            print(f"resolve-model-tiers: {path}: top-level model not in a plain string form; left as is", file=sys.stderr)
            return
        updated = head + original[head_end:]
    if tomllib.loads(updated).get("model") != wanted:
        raise ValueError(f"{path}: model rewrite did not round-trip")
    write_atomic(path, updated, 0o600)


def codex_profiles(home, resolved):
    for tier, effort in PROFILE_EFFORT.items():
        path = home / f"{tier}.config.toml"
        body = MANAGED + f"model = {json.dumps(resolved[tier])}\nmodel_reasoning_effort = {json.dumps(effort)}\n"
        if path.is_symlink() or (path.exists() and not path.read_text().startswith(MANAGED)):
            print(f"resolve-model-tiers: leaving unmanaged profile {path}", file=sys.stderr)
            continue
        if path.exists() and path.read_text() == body:
            continue
        write_atomic(path, body, 0o600)


def codex_agents(src, dest, tiers, resolved):
    swap = {tiers["floor"][tier]: resolved[tier] for tier in tiers["floor"]}
    if dest.is_symlink():
        dest.unlink()
    dest.mkdir(parents=True, exist_ok=True)
    manifest = dest / MANIFEST
    previous = set(manifest.read_text().split()) if manifest.exists() else set()
    names = []
    for source in sorted(src.glob("*.toml")):
        text = source.read_text()
        data = tomllib.loads(text)
        slug = data.get("model")
        if isinstance(slug, str) and swap.get(slug, slug) != slug:
            head_end = m.start() if (m := TABLE.search(text)) else len(text)
            head, _ = TOP_MODEL.subn(f"model = {json.dumps(swap[slug])}", text[:head_end], count=1)
            text = head + text[head_end:]
            check = tomllib.loads(text)
            if check.pop("model", None) != swap[slug] or check != {k: v for k, v in data.items() if k != "model"}:
                raise ValueError(f"{source.name}: model rewrite did not round-trip")
        target = dest / source.name
        names.append(source.name)
        if target.is_symlink():
            target.unlink()
        if target.exists() and target.read_text() == text:
            continue
        write_atomic(target, text, 0o644)
    for stale in sorted(previous - set(names)):
        path = dest / stale
        if "/" not in stale and path.is_file() and not path.is_symlink():
            path.unlink()
    listing = "".join(f"{name}\n" for name in names)
    if not manifest.exists() or manifest.read_text() != listing:
        write_atomic(manifest, listing, 0o644)


def default_catalog():
    home = os.environ.get("CODEX_HOME") or str(Path.home() / ".codex")
    return Path(home) / "models_cache.json"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--tiers", type=Path, required=True, help="JSON of model-tiers.nix `openai`")
    parser.add_argument("--catalog", type=Path, help="Codex models_cache.json (default: $CODEX_HOME)")
    parser.add_argument("--warn-floor", action="store_true", help="report floors older than the catalog")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("resolve")
    sub.add_parser("copilot-settings").add_argument("path", type=Path)
    sub.add_parser("codex-config").add_argument("path", type=Path)
    sub.add_parser("codex-profiles").add_argument("home", type=Path)
    agents = sub.add_parser("codex-agents")
    agents.add_argument("src", type=Path)
    agents.add_argument("dest", type=Path)
    args = parser.parse_args(argv)

    tiers = json.loads(args.tiers.read_text())
    catalog = load_catalog(args.catalog or default_catalog())
    resolved = resolve(tiers, catalog)
    if args.warn_floor:
        for note in floor_lag(tiers, resolved):
            print(note, file=sys.stderr)
    if args.cmd == "resolve":
        print(json.dumps(resolved, indent=2))
    elif args.cmd == "copilot-settings":
        copilot_settings(args.path, resolved)
    elif args.cmd == "codex-config":
        codex_config(args.path, tiers, catalog, resolved)
    elif args.cmd == "codex-profiles":
        codex_profiles(args.home, resolved)
    else:
        codex_agents(args.src, args.dest, tiers, resolved)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, tomllib.TOMLDecodeError) as error:
        print(f"resolve-model-tiers: {error}", file=sys.stderr)
        sys.exit(1)
