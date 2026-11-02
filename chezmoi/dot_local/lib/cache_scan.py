"""Read-only native session audit. Uses the standard library and zstdcat."""

import collections
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

if os.environ.get("AGENT_TOOLS_LIB"):
    sys.path.insert(0, os.environ["AGENT_TOOLS_LIB"])
from agent_tools.events import (
    Event,
    body,
    command,
    decode,
    failure,
    normalize_hook,
    heuristic_output,
    category,
    excerpt,
    reconcile,
)
from agent_tools.paths import agent_homes, capture_root, log_roots
from agent_tools.event_index import EventIndex


def read(path):
    try:
        if path.suffix == ".zst":
            result = subprocess.run(
                ["zstdcat", str(path)], capture_output=True, text=True, errors="replace"
            )
            return result.stdout if result.returncode == 0 else ""
        return path.read_text(errors="replace")
    except OSError:
        return ""


def unique(paths):
    seen = set()
    for path in paths:
        real = path.resolve()
        if real not in seen:
            seen.add(real)
            yield path


def timestamp(value, fallback):
    try:
        if isinstance(value, (int, float)):
            return float(value) / (1000 if value > 10**11 else 1)
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except (ValueError, TypeError, AttributeError):
        return fallback


def compact(value, length=180):
    if not isinstance(value, str):
        value = json.dumps(value, ensure_ascii=False)
    return " ".join(value.split())[:length]


def result_parts(output):
    """Keep independent orchestration results separate instead of flattening.

    Native exec stores either a text-block list or a Script completed wrapper
    containing JSON lines. Promise.allSettled and tagged outputs wrap each child
    under value/result. Never search within a completed command's output, where
    JSON and error examples are ordinary command data.
    """
    value = decode(output)
    if isinstance(value, list):
        for child in value:
            yield from result_parts(child)
    elif isinstance(value, dict):
        if any(key in value for key in ("exit_code", "isError", "is_error", "error")):
            yield value
        elif value.get("status") == "rejected":
            yield {
                "is_error": True,
                "output": value.get("reason", "rejected tool call"),
            }
        else:
            for key in ("text", "content", "result", "value"):
                if key in value:
                    yield from result_parts(value[key])
                    break
            else:
                yield value
    else:
        text = body(value)
        if text.startswith("Script completed") and "\nOutput:\n" in text:
            text = text.split("\nOutput:\n", 1)[1]
        # Multiple printed JSON results are separate children. Decode only at
        # the start of the payload, never arbitrary JSON quoted in tool output.
        remaining, parsed = text.lstrip(), []
        decoder = json.JSONDecoder()
        while remaining.startswith(("{", "[")):
            try:
                child, end = decoder.raw_decode(remaining)
            except ValueError:
                break
            parsed.append(child)
            remaining = remaining[end:].lstrip()
        if parsed and not remaining:
            for child in parsed:
                yield from result_parts(child)
        else:
            yield text


def codex_roots(home):
    return agent_homes("codex", home)


def capture_roots(home):
    cache = Path(os.environ.get("XDG_CACHE_HOME", home / ".cache"))
    roots = [capture_root(home)]
    if os.environ.get("CACHE_DIR"):
        roots.append(Path(os.environ["CACHE_DIR"]) / "agent-capture")
    roots.extend(
        cache / agent / "agent-capture" for agent in ("claude", "copilot", "codex")
    )
    return list(unique(root for root in roots if root.is_dir()))


def native_paths(home):
    paths = []
    for root in codex_roots(home):
        for folder in ("sessions", "archived_sessions"):
            paths.extend((p, "codex") for p in (root / folder).rglob("*.jsonl"))
    for root in agent_homes("claude", home):
        paths.extend((p, "claude") for p in (root / "projects").rglob("*.jsonl"))
    for root in agent_homes("copilot", home):
        paths.extend(
            (p, "copilot") for p in (root / "session-state").glob("*/events.jsonl")
        )
    for root in capture_roots(home):
        for agent in ("codex", "claude", "copilot"):
            pattern = "events.jsonl" if agent == "copilot" else "*.jsonl"
            paths.extend((p, agent) for p in (root / "capture" / agent).rglob(pattern))
    seen = set()
    for path, agent in paths:
        real = path.resolve()
        if real not in seen:
            seen.add(real)
            yield path, agent


def hook_failures(home):
    for root in capture_roots(home):
        for path in (root / "events").glob("*/*/events.jsonl"):
            try:
                with path.open(errors="replace") as stream:
                    for line_number, line in enumerate(stream, 1):
                        try:
                            event = json.loads(line)
                        except ValueError:
                            continue
                        if not isinstance(event, dict):
                            continue
                        name = str(event.get("event", "")).lower()
                        if name not in (
                            "posttoolusefailure",
                            "stopfailure",
                            "erroroccurred",
                            "permissiondenied",
                        ):
                            continue
                        payload = normalize_hook(event.get("payload", {}))
                        if not payload:
                            continue
                        stamp = timestamp(
                            event.get("captured_at", event.get("timestamp")),
                            path.stat().st_mtime,
                        )
                        yield Event(
                            stamp,
                            str(event.get("session_id", "unknown")),
                            str(event.get("agent", "unknown")),
                            str(payload.get("tool_name", name)),
                            command(
                                payload.get("tool_input", payload.get("tool_args", {}))
                            ),
                            body(payload.get("error", payload.get("message", payload))),
                            "error",
                            sources=[{"path": str(path), "line": line_number}],
                            origin="hook",
                            call_id=payload.get(
                                "tool_use_id", payload.get("tool_call_id")
                            ),
                        )
            except OSError:
                continue


def native_events(path, agent, include_messages=False):
    sid = path.parent.name if agent == "copilot" else path.stem
    fallback = path.stat().st_mtime
    calls, processes = {}, {}
    line_number, child_number, cid, origin = 0, 0, None, "native"
    chain = hashlib.sha256()

    def emit(row):
        return Event(
            *row,
            sources=[{"path": str(path), "line": line_number}],
            call_id=str(cid) if cid is not None else None,
            child=child_number,
            origin=origin,
            record_key=chain.hexdigest(),
        )

    # Stream once: retaining only provenance and emitted events avoids rereading
    # a transcript per tool result or per cache-log session.
    with path.open(errors="replace") as stream:
        for line_number, raw in enumerate(stream, 1):
            chain.update(raw.rstrip("\r\n").encode("utf-8", "replace"))
            child_number, cid, origin = 0, None, "native"
            try:
                event = json.loads(raw)
            except ValueError:
                continue
            if not isinstance(event, dict):
                continue
            data = (
                event.get("payload", {}) if agent == "codex" else event.get("data", {})
            )
            if not isinstance(data, dict):
                continue
            kind = event.get("type")
            ts = timestamp(event.get("timestamp", data.get("timestamp")), fallback)
            if kind == "session_meta":
                sid = data.get("id", data.get("session_id", sid))
            if agent == "codex":
                kind = data.get("type")
                if kind in ("function_call", "custom_tool_call"):
                    args = data.get("arguments", data.get("input", ""))
                    parsed = decode(args)
                    cmd = command(args)
                    if data.get("name", "").endswith("write_stdin") and isinstance(
                        parsed, dict
                    ):
                        cmd = processes.get(str(parsed.get("session_id")), cmd)
                    if data.get("call_id") is not None:
                        calls[data["call_id"]] = (data.get("name", "?"), cmd)
                elif kind in ("function_call_output", "custom_tool_call_output"):
                    tool, cmd = calls.get(data.get("call_id"), ("?", ""))
                    cid = data.get("call_id")
                    origin = "wrapper"
                    out = data.get("output", "")
                    parts = list(result_parts(out))
                    parent_cid = cid
                    for index, part in enumerate(parts, 1):
                        explicit_cid = part.get("call_id") if isinstance(part, dict) else None
                        # Own call IDs identify an execution across representations.
                        # Positions distinguish children known only by their parent.
                        cid = explicit_cid if explicit_cid is not None else parent_cid
                        child_number = 0 if explicit_cid is not None else index if len(parts) > 1 else 0
                        process = (
                            part.get("session_id") if isinstance(part, dict) else None
                        )
                        match = re.search(r"session ID[: ]+(\d+)", body(part))
                        child_cmd = (
                            command(part)
                            if isinstance(part, dict)
                            and any(k in part for k in ("cmd", "command"))
                            else cmd
                        )
                        if process is not None or match:
                            processes[
                                str(process if process is not None else match[1])
                            ] = child_cmd
                        if failure(part):
                            child_tool = (
                                f"{tool} child={index}" if len(parts) > 1 else tool
                            )
                            yield emit(
                                (
                                    ts,
                                    sid,
                                    agent,
                                    child_tool,
                                    child_cmd,
                                    body(part),
                                    "error",
                                )
                            )
                elif kind == "item_completed":
                    item = data.get("item", {})
                    cid = item.get("call_id", data.get("call_id"))
                    child_number = 0 if item.get("call_id") is not None else item.get("child", 0)
                    origin = "command-execution"
                    if item.get("type") == "CommandExecution" and item.get(
                        "exit_code"
                    ) not in (None, 0):
                        yield emit(
                            (
                                ts,
                                sid,
                                agent,
                                "exec_command",
                                body(item.get("command")),
                                body(item.get("aggregated_output")),
                                "error",
                            )
                        )
                    elif item.get("type") == "McpToolCall" and str(
                        item.get("status", "")
                    ).lower() in ("failed", "error"):
                        yield emit(
                            (
                                ts,
                                sid,
                                agent,
                                item.get("tool", "?"),
                                command(item.get("arguments")),
                                body(item.get("result")),
                                "error",
                            )
                        )
                elif kind == "message" and include_messages:
                    role = data.get("role")
                    if role in ("user", "assistant"):
                        yield emit(
                            (ts, sid, agent, role, "", body(data.get("content")), role)
                        )
            elif agent == "copilot":
                if kind == "tool.execution_start":
                    calls[data.get("toolCallId")] = (
                        data.get("toolName", "?"),
                        command(data.get("arguments")),
                    )
                elif kind == "tool.execution_complete" and data.get("success") is False:
                    cid = data.get("toolCallId")
                    tool, cmd = calls.get(cid, ("?", ""))
                    yield emit(
                        (ts, sid, agent, tool, cmd, body(data.get("error")), "error")
                    )
                elif include_messages and kind in ("user.message", "assistant.message"):
                    role = kind.split(".")[0]
                    yield emit(
                        (ts, sid, agent, role, "", body(data.get("content")), role)
                    )
            else:
                message = event.get("message", {})
                content = (
                    message.get("content", []) if isinstance(message, dict) else []
                )
                if include_messages and kind in ("user", "assistant"):
                    text_content = (
                        content
                        if isinstance(content, str)
                        else "\n".join(
                            body(item.get("text"))
                            for item in content
                            if isinstance(item, dict) and item.get("type") == "text"
                        )
                        if isinstance(content, list)
                        else ""
                    )
                    if text_content:
                        yield emit((ts, sid, agent, kind, "", text_content, kind))
                if not isinstance(content, list):
                    continue
                for item in content:
                    if not isinstance(item, dict):
                        continue
                    if item.get("type") == "tool_use":
                        calls[item.get("id")] = (
                            item.get("name", "?"),
                            command(item.get("input")),
                        )
                    elif (
                        item.get("type") == "tool_result"
                        and item.get("is_error") is True
                    ):
                        cid = item.get("tool_use_id")
                        tool, cmd = calls.get(cid, ("?", ""))
                        yield emit(
                            (
                                ts,
                                sid,
                                agent,
                                tool,
                                cmd,
                                body(item.get("content")),
                                "error",
                            )
                        )


def log_events(roots):
    for path in unique(
        p
        for root in roots
        for p in root.glob("session_*.log*")
        if re.fullmatch(r"session_[^.]+\.log(?:\.zst)?", p.name)
    ):
        fallback = path.stat().st_mtime
        sid = path.name.removeprefix("session_").split(".log")[0]
        text = read(path)
        starts = list(re.finditer(r"(?m)^## ", text))
        for index, start in enumerate(starts):
            end = starts[index + 1].start() if index + 1 < len(starts) else len(text)
            rec = text[start.end() : end]
            line_number = text.count("\n", 0, start.start()) + 1
            header = re.match(r"\[([^]]+)\]", rec)
            cmd = re.search(r"(?ms)^CMD: (.*?)(?=^STDOUT:|^STDERR:|^---|\Z)", rec)
            cmd = cmd[1].strip() if cmd else ""
            status = re.search(r"status=(\w+)", rec.split("\n", 1)[0])
            if not heuristic_output(cmd, status[1] if status else "unknown"):
                continue
            output = re.search(r"(?ms)^(?:STDOUT|STDERR):\n(.*)", rec)
            if output:
                yield Event(
                    timestamp(header[1] if header else None, fallback),
                    sid,
                    "cache",
                    "Bash",
                    cmd,
                    output[1],
                    "heuristic",
                    sources=[{"path": str(path), "line": line_number}],
                    origin="heuristic",
                )


def families(roots, cutoff, date_filter, limit):
    extensions = {".sh", ".bash", ".zsh", ".py", ".jq", ".graphql", ".sql", ".js", ".ts", ".go", ".mjs", ".nix"}
    excluded = {".git", "node_modules", "vendor", "site-packages", "dist", "build", "assets", "screenshots", "generated", "gh-graphql-snapshots", "trace", "traces", "playwright-report", "test-results", "blob-report"}
    # Path tokens describe the helper's purpose. Content signals are explicit
    # service/tool syntax, not generic words such as thread, browser or stack.
    rules = [("github-review", r"github|graphql|reviews?|threads?|gh-pr", r"\bgh\s+(?:api|pr)\b|api\.github\.com|github\.com/[^/\s]+/[^/\s]+/(?:pull|issues)"),
             ("cloud-triage", r"cloudformation|cfn|aws|stacks?|ecs|lambda", r"\baws\s+(?:cloudformation|ecs|lambda|sts|s3|logs)\b|\b(?:import|from)\s+boto3\b"),
             ("database", r"postgres|database|sql|rds", r"\b(?:psql|pg_dump)\b|\bimport\s+psycopg"),
             ("git-worktree", r"worktree|rebase|cherry-pick", r"\bgit\s+(?:worktree|rebase|cherry-pick)\b"),
             ("ticket-docs", r"jira|confluence|ticket", r"\bjira-get\b|/rest/api/(?:2|3)/issue"),
             ("browser", r"playwright|browser|screenshot", r"(?:from|import)\s+playwright\b|@playwright/|\bplaywright\s+(?:test|screenshot)\b"),
             ("verification", r"verify|verification|validation|acceptance|check", None)]
    hashes, counts, examples = set(), collections.Counter(), collections.defaultdict(list)
    types = collections.defaultdict(collections.Counter)
    candidates = duplicates = pruned_dirs = skipped_generated = repository_trees = 0
    for root in roots:
        for current, dirs, files in os.walk(root):
            if Path(current).name == "agent-capture":
                dirs[:] = [d for d in dirs if d == "capture"]
                files = []
            markers = set(dirs) | set(files)
            # Fetched clones and unpacked source snapshots contain product
            # code, not reusable helpers authored in the operational cache.
            manifests = {".github", "package.json", "go.mod", "flake.nix", "pyproject.toml"}
            if Path(current) != root and (".git" in markers or (".gitignore" in markers and manifests.intersection(markers))):
                repository_trees += 1
                dirs[:] = []
                continue
            kept = [d for d in dirs if d not in excluded and not d.startswith("gh-graphql-") and not re.match(r"(?:\.?venv|\.?test[-_]venv)(?:\d|[-_]|$)", d)]
            pruned_dirs += len(dirs) - len(kept)
            dirs[:] = kept
            for name in sorted(files):
                path = Path(current, name)
                logical = Path(name.removesuffix(".zst"))
                if logical.suffix not in extensions:
                    continue
                if logical.name.endswith((".min.js", ".d.ts")) or re.search(r"[.-][0-9a-f]{8,}\.(?:js|mjs)$", logical.name):
                    skipped_generated += 1
                    continue
                # gh-graphql snapshots inputs as <tag>-YYYYmmdd-HHMMSS.ext.
                if logical.suffix in (".graphql", ".jq") and re.search(r"-\d{8}-\d{6}\.(?:graphql|jq)$", logical.name):
                    skipped_generated += 1
                    continue
                try:
                    mtime = path.stat().st_mtime
                    if mtime < cutoff or (date_filter and not dt.datetime.fromtimestamp(mtime).isoformat().startswith(date_filter)):
                        continue
                    text = read(path)
                except OSError:
                    continue
                if not text:
                    continue
                candidates += 1
                digest = hashlib.sha256(text.encode()).digest()
                if digest in hashes:
                    duplicates += 1
                    continue
                hashes.add(digest)
                relative = logical.name.lower()
                content = text[:8192]
                label = next((label for label, path_pattern, content_pattern in rules
                              if re.search(r"(?<![a-z])(?:" + path_pattern + r")(?![a-z])", relative)
                              or (content_pattern and re.search(content_pattern, content))), "other-" + logical.suffix[1:])
                counts[label] += 1
                types[label][logical.suffix] += 1
                if len(examples[label]) < 3:
                    examples[label].append(name)
    print(f"  candidates={candidates} unique={len(hashes)} duplicates={duplicates} pruned_dirs={pruned_dirs} generated_files={skipped_generated} repository_trees={repository_trees}")
    repeated = [(label, n) for label, n in counts.most_common() if n >= 2]
    for label, n in repeated[:limit]:
        provenance = ",".join(f"{suffix}:{count}" for suffix, count in types[label].most_common())
        print(f"  {label:<20} {n:<4} [{provenance}] {', '.join(examples[label])}")
    if not repeated:
        print("  (none recurring)")


def main():
    mode, days, limit, date_filter, session = sys.argv[1:]
    days, limit = int(days), int(limit)
    home = Path.home()
    if mode == "roots":
        for root in log_roots(home):
            print(root)
        return 0
    cutoff = time.time() - days * 86400
    roots = log_roots(home)

    def eligible(event):
        ts, sid = event[:2]
        return (
            ts >= cutoff
            and (not session or session in sid)
            and (
                not date_filter
                or dt.datetime.fromtimestamp(ts).isoformat().startswith(date_filter)
            )
        )

    events = []
    index = EventIndex(home)
    for path, agent in native_paths(home):
        if (
            agent == "codex"
            and re.fullmatch(r"[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}", session)
            and session not in path.name
        ):
            continue
        try:
            events.extend(
                e for e in index.events(path, agent, native_events) if eligible(e)
            )
        except OSError:
            continue
    index.save()
    events = sorted(reconcile(events), key=lambda e: e.timestamp)
    errors = [e for e in events if e.kind == "error"]
    ambiguous = [e for e in errors if e.ambiguous]
    selected = errors[-limit:] if limit else []
    captured_errors = sorted(
        (e for e in hook_failures(home) if eligible(e)), key=lambda e: e[0]
    )
    signals = [e for e in log_events(roots) if eligible(e) and category(e[5])]

    if mode in ("json", "json-full"):
        # Record count and text lengths are independent bounds. Sources/index retain full evidence.
        full_output = mode == "json-full"
        observations = {
            "events": errors,
            "hook_observations": captured_errors,
            "heuristic_signals": sorted(signals, key=lambda e: e.timestamp),
        }
        record_counts = {
            name: {
                "total": len(rows),
                "selected": min(limit, len(rows)),
                "omitted": max(0, len(rows) - limit),
            }
            for name, rows in observations.items()
        }
        evidence = {
            name: [e.evidence(full_output=full_output) for e in (rows[-limit:] if limit else [])]
            for name, rows in observations.items()
        }
        print(
            json.dumps(
                {
                    "schema": 1,
                    "error_observations": len(errors),
                    "unique_executions": None
                    if ambiguous or any(not e.call_id for e in errors)
                    else len(errors),
                    "ambiguous_observations": len(ambiguous),
                    "record_limit": limit,
                    "record_counts": record_counts,
                    **evidence,
                    "index": index.stats(),
                },
                ensure_ascii=False,
            )
        )
        return 0

    print(
        "NATIVE TRANSCRIPTS (live and cached)"
        if mode == "transcript"
        else "ACTUAL TOOL ERRORS"
    )
    for event in selected:
        ts, sid, agent, tool, cmd, output, _ = event
        stamp = dt.datetime.fromtimestamp(ts).isoformat(timespec="seconds")
        uncertainty = " [possible overlap; observation]" if event.ambiguous else ""
        print(
            f"  [{stamp}] {agent} session={sid} {tool}: {compact(cmd, 140)}{uncertainty}"
        )
        print(f"    → {excerpt(output)}")
    if not selected:
        print("  (none found in retained native transcripts)")
    if ambiguous:
        print(
            f"  error_observations={len(errors)} ambiguous_observations={len(ambiguous)} unique_executions=unknown shown={len(selected)}"
        )
    else:
        print(f"  errors={len(errors)} shown={len(selected)} (native observations)")
        if any(not e.call_id for e in errors):
            print("  unique_executions=unknown (missing execution IDs)")
    if captured_errors:
        print(
            "\nCAPTURED HOOK FAILURES (separate observations; may overlap native errors)"
        )
        for ts, sid, agent, tool, cmd, output, _ in (
            captured_errors[-limit:] if limit else []
        ):
            print(
                f"  [{dt.datetime.fromtimestamp(ts).isoformat(timespec='seconds')}] {agent} session={sid} {tool}: {compact(cmd, 140)}"
            )
            print(f"    → {excerpt(output)}")
    if mode == "transcript":
        for role, title in (("user", "PROMPTS"), ("assistant", "DECISIONS")):
            print(title)
            for event in (
                [e for e in events if e.kind == role][-limit:] if limit else []
            ):
                print(
                    f"  [{dt.datetime.fromtimestamp(event[0]).isoformat(timespec='seconds')}] session={event[1]} {compact(event[5])}"
                )
        return 0 if events or captured_errors else 3
    print("\nHEURISTIC FAILURE SIGNALS")
    counts, examples = collections.Counter(), {}
    for event in signals:
        label = category(event[5])
        counts[label] += 1
        examples[label] = compact(event[4], 100)
    if mode == "classify":
        print(f"cache-scan --classify window={days}d")
        print("CATEGORY             COUNT")
    for label, n in counts.most_common():
        print(f"  {label:<20} {n:<4} {examples[label]}")
    if not counts:
        print("  (none)")
    if mode == "audit":
        print("\nSCRIPT ARTIFACT FAMILIES")
        families(roots, cutoff, date_filter, limit)
    return 0


if __name__ == "__main__":
    sys.exit(main())
