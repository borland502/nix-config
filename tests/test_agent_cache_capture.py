#!/usr/bin/env python3
"""Fixture tests for the model-free agent cache capture engine."""

from __future__ import annotations

import json
import os
from pathlib import Path
import resource
import runpy
import stat
import subprocess
import tempfile
import threading
import time
import unittest
from unittest import mock

import fcntl


REPO = Path(__file__).resolve().parents[1]
CAPTURE = REPO / "ai-tools/scripts/agent-cache-capture"
SWEEPER = REPO / "ai-tools/scripts/sweep-agent-assets"
CAPTURE_API = runpy.run_path(str(CAPTURE), run_name="agent_cache_capture_test")


class CaptureFixture(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.home = self.base / "home"
        self.cache = self.base / "cache"
        self.config = self.home / ".config"
        self.tmp = self.base / "tmp"
        for path in (self.home, self.config, self.tmp):
            path.mkdir(parents=True, exist_ok=True)
        self.env = dict(
            os.environ,
            HOME=str(self.home),
            XDG_CONFIG_HOME=str(self.config),
            AGENT_CACHE_CAPTURE_ROOT=str(self.cache),
            CODEX_HOME=str(self.config / "codex"),
            CLAUDE_CONFIG_DIR=str(self.config / "claude"),
            COPILOT_HOME=str(self.config / "copilot"),
            TMPDIR=str(self.tmp),
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def run_capture(
        self, *args: str, input_text: str | None = None, check: bool = True
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(CAPTURE), *args],
            input=input_text,
            text=True,
            capture_output=True,
            env=self.env,
            check=check,
        )

    def manifests(self) -> list[dict[str, object]]:
        result = []
        for path in sorted((self.cache / "manifests").glob("*/*.json")):
            result.append(json.loads(path.read_text()))
        return result

    def entries(self) -> list[dict[str, object]]:
        return [entry for manifest in self.manifests() for entry in manifest["files"]]

    def captured_for(self, source: Path) -> Path:
        source_resolved = str(source.resolve())
        matches = [e for e in self.entries() if e["source_path"] == source_resolved]
        self.assertEqual(len(matches), 1, matches)
        return self.cache / str(matches[0]["destination"])


class AgentCacheCaptureTests(CaptureFixture):
    def test_hook_preserves_original_normalizes_fields_and_safely_keys_session(
        self,
    ) -> None:
        payload = {
            "sessionId": "../../session with spaces",
            "toolName": "Read",
            "toolOutput": {"large": "x" * 1000},
            "transcriptPath": str(self.config / "claude/projects/demo/session.jsonl"),
        }
        self.run_capture(
            "--agent",
            "claude",
            "--event",
            "PostToolUse",
            input_text=json.dumps(payload),
        )

        event_files = list((self.cache / "events/claude").glob("*/events.jsonl"))
        self.assertEqual(len(event_files), 1)
        self.assertNotIn("..", event_files[0].parent.name)
        envelope = json.loads(event_files[0].read_text())
        self.assertEqual(envelope["agent"], "claude")
        self.assertEqual(envelope["event"], "PostToolUse")
        self.assertEqual(envelope["session_id"], payload["sessionId"])
        self.assertEqual(envelope["payload"], payload)
        self.assertEqual(envelope["normalized"]["tool_name"], "Read")
        self.assertNotIn("tool_output", envelope["normalized"])
        self.assertEqual(
            envelope["references"],
            [{"kind": "transcript", "path": payload["transcriptPath"]}],
        )
        self.assertEqual(stat.S_IMODE(event_files[0].stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.cache.stat().st_mode), 0o700)

    def test_hook_records_errors_and_concurrent_appends_are_valid_jsonl(self) -> None:
        processes = [
            subprocess.Popen(
                [str(CAPTURE), "--agent", "codex", "--event", "tool_error"],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=self.env,
            )
            for _ in range(12)
        ]
        barrier = threading.Barrier(len(processes) + 1)
        outputs: list[tuple[str, str] | None] = [None] * len(processes)

        def send(number: int, process: subprocess.Popen[str]) -> None:
            barrier.wait()
            outputs[number] = process.communicate(
                json.dumps({"session_id": "same", "error": f"failure-{number}"})
            )

        workers = [
            threading.Thread(target=send, args=(number, process))
            for number, process in enumerate(processes)
        ]
        for worker in workers:
            worker.start()
        barrier.wait()
        for worker in workers:
            worker.join()
        self.assertTrue(all(process.returncode == 0 for process in processes))
        self.assertTrue(
            all(output is not None and not output[1] for output in outputs), outputs
        )
        event_file = next((self.cache / "events/codex").glob("*/events.jsonl"))
        events = [json.loads(line) for line in event_file.read_text().splitlines()]
        self.assertEqual(len(events), 12)
        self.assertEqual(
            {e["payload"]["error"] for e in events}, {f"failure-{n}" for n in range(12)}
        )

    def test_malformed_and_oversized_input_are_reported_without_normal_event(
        self,
    ) -> None:
        malformed = self.run_capture(
            "--agent", "copilot", "--event", "error", input_text="not json", check=False
        )
        self.assertEqual(malformed.returncode, 1)
        self.assertIn("invalid JSON", malformed.stderr)

        self.env["AGENT_CACHE_EVENT_MAX_BYTES"] = "32"
        oversized = self.run_capture(
            "--agent",
            "copilot",
            "--event",
            "prompt",
            input_text=json.dumps({"session_id": "s", "value": "x" * 100}),
            check=False,
        )
        self.assertEqual(oversized.returncode, 3)
        self.assertIn("too large", oversized.stderr)
        self.assertEqual(
            list((self.cache / "events/copilot").glob("*/events.jsonl")), []
        )
        self.assertEqual(len(list((self.cache / "overflow/copilot").glob("*.json"))), 1)
        self.assertEqual(
            len(list((self.cache / "overflow/copilot").glob("*.partial"))), 0
        )

    def test_reconcile_discovers_all_agents_and_deduplicates_legacy_aliases(
        self,
    ) -> None:
        codex = self.config / "codex"
        codex_file = codex / "sessions/2026/one.jsonl"
        claude_file = self.config / "claude/projects/work/session.jsonl"
        claude_tool = self.config / "claude/projects/work/s1/tool-results/.hidden"
        claude_subagent = self.config / "claude/projects/work/s1/subagents/a.jsonl"
        claude_history = self.config / "claude/file-history/s1/change.txt"
        copilot_event = self.config / "copilot/session-state/c1/events.jsonl"
        copilot_file = self.config / "copilot/session-state/c1/files/a/note.txt"
        copilot_meta = self.config / "copilot/session-state/c1/workspace.yaml"
        copilot_log = self.config / "copilot/logs/client.log"
        scratch = self.tmp / "claude-100/work/s1/scratchpad/.draft"
        for number, path in enumerate(
            (
                codex_file,
                claude_file,
                claude_tool,
                claude_subagent,
                claude_history,
                copilot_event,
                copilot_file,
                copilot_meta,
                copilot_log,
                scratch,
            )
        ):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(f"content-{number}")
        (self.home / ".codex").symlink_to(codex, target_is_directory=True)

        self.run_capture("--reconcile")

        sources = {entry["source_path"] for entry in self.entries()}
        expected = {
            str(path.resolve())
            for path in (
                codex_file,
                claude_file,
                claude_tool,
                claude_subagent,
                claude_history,
                copilot_event,
                copilot_file,
                copilot_meta,
                copilot_log,
                scratch,
            )
        }
        self.assertEqual(sources, expected)
        self.assertEqual(
            sum(source == str(codex_file.resolve()) for source in sources), 1
        )

    def test_reconcile_preserves_hierarchy_duplicate_basenames_mtime_and_manifest(
        self,
    ) -> None:
        first = self.config / "codex/sessions/a/shared.jsonl"
        second = self.config / "codex/sessions/b/shared.jsonl"
        for path, content in ((first, "first"), (second, "second")):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        recent_ns = time.time_ns() - 86_400_000_000_000
        os.utime(first, ns=(recent_ns,) * 2)

        self.run_capture("--reconcile")

        first_dest = self.captured_for(first)
        second_dest = self.captured_for(second)
        self.assertNotEqual(first_dest, second_dest)
        self.assertEqual(first_dest.read_text(), "first")
        self.assertEqual(second_dest.read_text(), "second")
        self.assertEqual(first_dest.stat().st_mtime_ns, first.stat().st_mtime_ns)
        entry = next(
            e for e in self.entries() if e["source_path"] == str(first.resolve())
        )
        self.assertEqual(entry["agent"], "codex")
        self.assertEqual(entry["size"], 5)
        self.assertEqual(entry["copy_cursor"], 5)
        self.assertEqual(len(str(entry["sha256"])), 64)
        self.assertEqual(stat.S_IMODE(first_dest.stat().st_mode), 0o600)

    def test_codex_configured_log_directory_is_discovered(self) -> None:
        codex = self.config / "codex"
        log_dir = self.base / "codex-runtime-logs"
        log_file = log_dir / "codex.log"
        log_dir.mkdir(parents=True)
        log_file.write_text("diagnostic")
        codex.mkdir(parents=True)
        (codex / "config.toml").write_text(f'log_dir = "{log_dir}"\n')

        self.run_capture("--reconcile")

        self.assertEqual(self.captured_for(log_file).read_text(), "diagnostic")

    def test_explicit_generated_artifact_roots_are_captured(self) -> None:
        paths = (
            self.config / "codex/visualizations/chart.json",
            self.config / "codex/computer-use/screenshot.png",
            self.config / "claude/debug/trace.log",
            self.config / "claude/paste-cache/paste.txt",
            self.config / "claude/plans/plan.md",
            self.config / "claude/tasks/task.json",
            self.config / "claude/todos/todo.json",
            self.config / "copilot/media-cache/image.png",
        )
        omitted = self.config / "codex/node_repl/node_modules/package/index.js"
        for path in (*paths, omitted):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(path.name)

        self.run_capture("--reconcile")

        captured = {entry["source_path"] for entry in self.entries()}
        self.assertTrue({str(path.resolve()) for path in paths}.issubset(captured))
        self.assertNotIn(str(omitted.resolve()), captured)

    def test_codex_log_dir_rejects_capture_root_to_prevent_recursion(self) -> None:
        codex = self.config / "codex"
        codex.mkdir(parents=True)
        self.cache.mkdir()
        sentinel = self.cache / "must-not-be-source.log"
        sentinel.write_text("sentinel")
        (codex / "config.toml").write_text(f'log_dir = "{self.cache}"\n')

        result = self.run_capture("--reconcile", "--dry-run")

        self.assertNotIn(str(sentinel), result.stdout)

    def test_same_size_rewrite_updates_but_unchanged_scan_does_not_replace(
        self,
    ) -> None:
        source = self.config / "codex/sessions/a.jsonl"
        source.parent.mkdir(parents=True)
        source.write_text("before")
        self.run_capture("--reconcile")
        destination = self.captured_for(source)
        first_inode = destination.stat().st_ino

        self.run_capture("--reconcile")
        self.assertEqual(destination.stat().st_ino, first_inode)

        source.write_text("after!")
        os.utime(source, ns=(source.stat().st_atime_ns, source.stat().st_mtime_ns + 1))
        self.run_capture("--reconcile")
        self.assertEqual(destination.read_text(), "after!")

    def test_symlinks_inside_sources_are_not_followed(self) -> None:
        outside = self.base / "outside-secret"
        outside.write_text("do not capture")
        source_dir = self.config / "copilot/session-state/s/files"
        source_dir.mkdir(parents=True)
        (source_dir / "escape").symlink_to(outside)
        safe = source_dir / "safe.txt"
        safe.write_text("safe")

        self.run_capture("--reconcile")

        sources = {entry["source_path"] for entry in self.entries()}
        self.assertIn(str(safe.resolve()), sources)
        self.assertNotIn(str(outside), sources)

    def test_native_child_root_symlink_is_not_allowlisted(self) -> None:
        credentials = self.base / "credential-store"
        credentials.mkdir()
        secret = credentials / "token.json"
        secret.write_text("secret")
        copilot = self.config / "copilot"
        copilot.mkdir()
        (copilot / "logs").symlink_to(credentials, target_is_directory=True)

        self.run_capture("--reconcile")

        self.assertNotIn(
            str(secret.resolve()), {e["source_path"] for e in self.entries()}
        )

    def test_event_reference_reconciles_allowlisted_custom_transcript_only(
        self,
    ) -> None:
        transcript = self.base / "custom/projects/job/session.jsonl"
        unsafe = self.base / "custom/credentials.json"
        for path in (transcript, unsafe):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(path.name)
        payload = {
            "session_id": "ref",
            "transcript_path": str(transcript),
            "agent_transcript_path": str(unsafe),
        }
        self.run_capture(
            "--agent", "claude", "--event", "stop", input_text=json.dumps(payload)
        )
        self.run_capture("--reconcile")

        sources = {entry["source_path"] for entry in self.entries()}
        self.assertIn(str(transcript.resolve()), sources)
        self.assertNotIn(str(unsafe.resolve()), sources)

    def test_failed_update_preserves_previous_good_mirror(self) -> None:
        source = self.config / "codex/sessions/a.jsonl"
        source.parent.mkdir(parents=True)
        source.write_text("good")
        self.run_capture("--reconcile")
        destination = self.captured_for(source)
        source.write_text("new!")

        def restrict_file_size() -> None:
            resource.setrlimit(resource.RLIMIT_FSIZE, (1, 1))

        failed = subprocess.run(
            [str(CAPTURE), "--reconcile"],
            text=True,
            capture_output=True,
            env=self.env,
            preexec_fn=restrict_file_size,
        )
        self.assertNotEqual(failed.returncode, 0)
        self.assertEqual(destination.read_text(), "good")

    def test_source_mutation_after_first_chunk_preserves_previous_mirror(self) -> None:
        source = self.base / "source.jsonl"
        destination = self.base / "mirror.jsonl"
        source.write_bytes(b"A" * (2 * 1024 * 1024))
        destination.write_bytes(b"last-good")
        source_stat = source.stat()
        original_open = Path.open

        class MutatingReader:
            def __init__(self, stream: object) -> None:
                self.stream = stream
                self.mutated = False

            def __enter__(self) -> "MutatingReader":
                return self

            def __exit__(self, *args: object) -> None:
                self.stream.close()

            def __getattr__(self, name: str) -> object:
                return getattr(self.stream, name)

            def read(self, size: int = -1) -> bytes:
                data = self.stream.read(size)
                if data and not self.mutated:
                    self.mutated = True
                    with original_open(source, "r+b") as writer:
                        writer.seek(1024 * 1024)
                        writer.write(b"B" * (1024 * 1024))
                        writer.flush()
                        os.fsync(writer.fileno())
                return data

        def patched_open(path: Path, *args: object, **kwargs: object) -> object:
            stream = original_open(path, *args, **kwargs)
            if path == source and (not args or args[0] == "rb"):
                return MutatingReader(stream)
            return stream

        with mock.patch.object(Path, "open", patched_open):
            with self.assertRaises(OSError):
                CAPTURE_API["atomic_copy"](source, destination, source_stat)
        self.assertEqual(destination.read_bytes(), b"last-good")

    def test_busy_file_is_deferred_without_starving_later_agent(self) -> None:
        codex_root = self.base / "native-codex"
        copilot_root = self.base / "native-copilot"
        codex_root.mkdir()
        copilot_root.mkdir()
        busy = codex_root / "busy.jsonl"
        stable = copilot_root / "stable.jsonl"
        busy.write_text("old-busy")
        stable.write_text("old-stable")
        source_type = CAPTURE_API["Source"]
        allow_all = CAPTURE_API["allow_all"]
        sources = [
            source_type("codex", "sessions", codex_root.resolve(), allow_all),
            source_type("copilot", "session-state", copilot_root.resolve(), allow_all),
        ]
        globals_dict = CAPTURE_API["reconcile"].__globals__

        with (
            mock.patch.dict(os.environ, self.env, clear=False),
            mock.patch.dict(
                globals_dict,
                {
                    "discover_static_sources": lambda: sources,
                    "referenced_sources": lambda _root, _persist: [],
                },
            ),
        ):
            self.assertEqual(CAPTURE_API["reconcile"](False, False), 0)
            busy_destination = self.captured_for(busy)
            stable_destination = self.captured_for(stable)
            busy.write_text("new-busy")
            stable.write_text("new-stable")
            real_atomic_copy = globals_dict["atomic_copy"]

            def defer_busy(
                source: Path, destination: Path, source_stat: os.stat_result
            ) -> str:
                if source.name == "busy.jsonl":
                    raise OSError("source changed during copy")
                return real_atomic_copy(source, destination, source_stat)

            with mock.patch.dict(globals_dict, {"atomic_copy": defer_busy}):
                rc = CAPTURE_API["reconcile"](False, False)

        self.assertNotEqual(rc, 0)
        self.assertEqual(busy_destination.read_text(), "old-busy")
        self.assertEqual(stable_destination.read_text(), "new-stable")

    def test_retention_skips_old_sources_backfills_explicitly_and_expires_cache(
        self,
    ) -> None:
        source = self.config / "codex/sessions/old.jsonl"
        source.parent.mkdir(parents=True)
        source.write_text("old")
        old = time.time() - (3 * 86400)
        os.utime(source, (old, old))
        self.env["CACHE_RETENTION_DAYS"] = "2"

        self.run_capture("--reconcile")
        self.assertNotIn(
            str(source.resolve()), {e["source_path"] for e in self.entries()}
        )

        self.run_capture("--reconcile", "--backfill")
        destination = self.captured_for(source)
        self.assertTrue(destination.exists())

        self.run_capture("--reconcile")
        self.assertFalse(destination.exists())
        self.assertNotIn(
            str(source.resolve()), {e["source_path"] for e in self.entries()}
        )

    def test_retention_expires_old_hook_session_directories(self) -> None:
        self.env["CACHE_RETENTION_DAYS"] = "2"
        payload = json.dumps({"session_id": "old-hook"})
        self.run_capture("--agent", "codex", "--event", "stop", input_text=payload)
        session_dir = next((self.cache / "events/codex").iterdir())
        old = time.time() - (3 * 86400)
        os.utime(session_dir / "events.jsonl", (old, old))

        self.run_capture("--reconcile")
        self.assertFalse((session_dir / "events.jsonl").exists())

    def test_retention_expires_only_old_regular_overflow_files(self) -> None:
        self.env["CACHE_RETENTION_DAYS"] = "2"
        overflow = self.cache / "overflow/codex"
        overflow.mkdir(parents=True)
        old_file = overflow / "old.json"
        recent_file = overflow / "recent.json"
        active_partial = overflow / "active.partial"
        outside = self.base / "outside-overflow"
        old_file.write_text("old")
        recent_file.write_text("recent")
        active_partial.write_text("still-writing")
        outside.write_text("outside")
        symlink = overflow / "old-link.json"
        symlink.symlink_to(outside)
        old = time.time() - (3 * 86400)
        os.utime(old_file, (old, old))
        os.utime(active_partial, (old, old))
        active_lock = active_partial.open("r+b")
        fcntl.flock(active_lock, fcntl.LOCK_EX)
        try:
            dry_run = self.run_capture("--reconcile", "--dry-run")

            self.assertIn(f"would expire: {old_file.resolve()}", dry_run.stdout)
            self.assertTrue(old_file.exists())
            self.assertTrue(recent_file.exists())
            self.assertTrue(active_partial.exists())
            self.assertTrue(symlink.is_symlink())

            self.run_capture("--reconcile")
        finally:
            fcntl.flock(active_lock, fcntl.LOCK_UN)
            active_lock.close()

        self.assertFalse(old_file.exists())
        self.assertTrue(recent_file.exists())
        self.assertTrue(active_partial.exists())
        self.assertTrue(symlink.is_symlink())
        self.assertEqual(outside.read_text(), "outside")

    def test_event_expiry_locks_and_rechecks_before_removing_event(self) -> None:
        root = self.cache.resolve()
        session = root / "events/codex/session"
        session.mkdir(parents=True)
        event_file = session / "events.jsonl"
        event_file.write_text("{}\n")
        old = time.time() - 86400
        os.utime(event_file, (old, old))
        lock_path = session / ".append.lock"
        lock_path.touch()
        lock = lock_path.open("r+b")
        fcntl.flock(lock, fcntl.LOCK_EX)
        started = threading.Event()
        errors: list[BaseException] = []

        def expire() -> None:
            started.set()
            try:
                CAPTURE_API["expire_event_sessions"](root, time.time() - 60, False)
            except BaseException as error:
                errors.append(error)

        worker = threading.Thread(target=expire)
        worker.start()
        started.wait(1)
        time.sleep(0.1)
        was_waiting = worker.is_alive()
        if event_file.exists():
            os.utime(event_file, None)
        fcntl.flock(lock, fcntl.LOCK_UN)
        lock.close()
        worker.join(2)

        self.assertTrue(was_waiting)
        self.assertEqual(errors, [])
        self.assertTrue(event_file.exists())

    def test_reference_cursor_keeps_partial_trailing_jsonl_record(self) -> None:
        transcript = self.base / "custom/projects/job/session.jsonl"
        transcript.parent.mkdir(parents=True)
        transcript.write_text("transcript")
        event_dir = self.cache / "events/claude/session"
        event_dir.mkdir(parents=True)
        event_file = event_dir / "events.jsonl"
        complete = json.dumps({"references": []}) + "\n"
        split = json.dumps(
            {"references": [{"kind": "transcript", "path": str(transcript)}]}
        )
        midpoint = len(split) // 2
        event_file.write_text(complete + split[:midpoint])

        self.run_capture("--reconcile")
        index = json.loads((self.cache / "runtime/reference-index.json").read_text())
        record = index["event_files"][str(event_file.resolve())]
        self.assertEqual(record["cursor"], len(complete.encode()))

        with event_file.open("a") as stream:
            stream.write(split[midpoint:] + "\n")
        self.run_capture("--reconcile")
        self.assertEqual(self.captured_for(transcript).read_text(), "transcript")

    def test_retention_expires_manifest_when_whole_source_root_disappears(self) -> None:
        self.env["CACHE_RETENTION_DAYS"] = "2"
        source = self.config / "codex/sessions/old.jsonl"
        source.parent.mkdir(parents=True)
        source.write_text("old")
        old = time.time() - (3 * 86400)
        os.utime(source, (old, old))
        self.run_capture("--reconcile", "--backfill")
        destination = self.captured_for(source)
        source.parent.rename(self.base / "removed-sessions")

        self.run_capture("--reconcile")

        self.assertFalse(destination.exists())

    def test_manifest_cannot_expire_a_path_outside_capture_root(self) -> None:
        self.env["CACHE_RETENTION_DAYS"] = "2"
        source = self.config / "codex/sessions/old.jsonl"
        source.parent.mkdir(parents=True)
        source.write_text("old")
        self.run_capture("--reconcile")
        manifest_path = next((self.cache / "manifests/codex").glob("*.json"))
        manifest = json.loads(manifest_path.read_text())
        manifest["files"][0]["destination"] = "capture/../../outside-victim"
        manifest["files"][0]["mtime_ns"] = 0
        manifest_path.write_text(json.dumps(manifest))
        victim = self.base / "outside-victim"
        victim.write_text("safe")

        result = self.run_capture("--reconcile", check=False)

        self.assertEqual(victim.read_text(), "safe")
        self.assertIn("refusing unsafe manifest destination", result.stderr)

    def test_capture_refuses_internal_symlink_ancestor(self) -> None:
        source = self.config / "codex/sessions/a.jsonl"
        source.parent.mkdir(parents=True)
        source.write_text("one")
        outside = self.base / "outside-destination"
        outside.mkdir()
        (self.cache / "capture").mkdir(parents=True)
        (self.cache / "capture/codex").symlink_to(outside, target_is_directory=True)

        result = self.run_capture("--reconcile", check=False)

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(outside.iterdir()), [])

    def test_concurrent_reconciliation_is_serialized(self) -> None:
        source = self.config / "codex/sessions/a.jsonl"
        source.parent.mkdir(parents=True)
        source.write_text("one")
        processes = [
            subprocess.Popen(
                [str(CAPTURE), "--reconcile"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=self.env,
            )
            for _ in range(2)
        ]
        outputs = [process.communicate() for process in processes]
        self.assertTrue(all(process.returncode == 0 for process in processes), outputs)
        self.assertEqual(self.captured_for(source).read_text(), "one")

    def test_dry_run_is_read_only_and_prune_is_refused(self) -> None:
        source = self.config / "codex/sessions/a.jsonl"
        source.parent.mkdir(parents=True)
        source.write_text("one")
        result = self.run_capture("--reconcile", "--dry-run")
        self.assertIn(str(source), result.stdout)
        self.assertFalse(self.cache.exists())

        refused = self.run_capture("--reconcile", "--prune", check=False)
        self.assertEqual(refused.returncode, 2)
        self.assertIn("never prunes", refused.stderr)

    def test_legacy_sweeper_delegates_without_accepting_prune(self) -> None:
        source = self.config / "codex/sessions/a.jsonl"
        source.parent.mkdir(parents=True)
        source.write_text("one")
        subprocess.run([str(SWEEPER), "--force"], env=self.env, check=True)
        self.assertEqual(self.captured_for(source).read_text(), "one")
        refused = subprocess.run(
            [str(SWEEPER), "--prune"], env=self.env, text=True, capture_output=True
        )
        self.assertEqual(refused.returncode, 2)


if __name__ == "__main__":
    unittest.main()
