#!/usr/bin/env python3
"""Synthetic native-session and cache-family integration regressions."""
import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCANNER = Path(__file__).resolve().parents[1] / "chezmoi/dot_local/bin/executable_cache-scan"

class CacheScanTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.codex = self.home / "custom-codex"
        self.now = dt.datetime.now(dt.timezone.utc)
        self.today = self.now.strftime("%Y-%m-%d")
        self.stamp = self.now.isoformat()

    def scan(self, *args):
        env = dict(os.environ, HOME=str(self.home), CODEX_HOME=str(self.codex))
        for key in ("CLAUDE_CONFIG_DIR", "COPILOT_HOME", "CACHE_DIR", "AGENT_CACHE_CAPTURE_ROOT"):
            env.pop(key, None)
        env.update(XDG_CONFIG_HOME=str(self.home / ".config"), XDG_CACHE_HOME=str(self.home / ".cache"))
        result = subprocess.run([str(SCANNER), *args], env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def write_session(self, name, records):
        p = self.codex / "sessions" / (name + ".jsonl")
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text("\n".join(json.dumps(x) for x in [{"type":"session_meta", "payload":{"id":name}}, *records]))
        return p

    def event(self, payload, stamp=None):
        return {"timestamp":stamp or self.stamp,"type":"response_item","payload":payload}

    def test_codex_errors_provenance_filters_and_running_outputs(self):
        records = [
            self.event({"type":"function_call","name":"exec_command","call_id":"a","arguments":json.dumps({"cmd":"false real-command"})}),
            self.event({"type":"function_call_output","call_id":"a","output":"Process exited with code 2\nFinal output:\nreal-failure"}),
            self.event({"type":"function_call","name":"exec_command","call_id":"b","arguments":json.dumps({"cmd":"long-job"})}),
            self.event({"type":"function_call_output","call_id":"b","output":"Process running with session ID 12\nOutput:\nError: preliminary"}),
            self.event({"type":"function_call","name":"write_stdin","call_id":"c","arguments":json.dumps({"session_id":12})}),
            self.event({"type":"function_call_output","call_id":"c","output":json.dumps({"exit_code":3,"output":"poll-failure"})}),
            self.event({"type":"function_call","name":"exec_command","call_id":"d","arguments":json.dumps({"cmd":"bat SKILL.md"})}),
            self.event({"type":"function_call_output","call_id":"d","output":json.dumps({"exit_code":0,"output":"fatal: documentation example"})}),
            {"type":"event_msg","timestamp":self.stamp,"payload":{"type":"item_completed","item":{"type":"CommandExecution","command":"missing-program","exit_code":127,"aggregated_output":"actual-missing"}}},
            self.event({"type":"function_call","name":"exec_command","call_id":"old","arguments":json.dumps({"cmd":"old-command"})}, "2001-01-01T00:00:00Z"),
            self.event({"type":"function_call_output","call_id":"old","output":"Process exited with code 1\nold-failure"}, "2001-01-01T00:00:00Z"),
        ]
        self.write_session("chosen", records)
        self.write_session("other", [self.event({"type":"function_call_output","call_id":"x","output":"Error: unrelated-tool-failure"})])
        out = self.scan("--audit", "--date", self.today, "--session", "chosen")
        for text in ("real-failure", "poll-failure", "long-job", "actual-missing", "false real-command", self.today, "chosen"):
            self.assertIn(text, out)
        for text in ("preliminary", "documentation example", "old-failure", "unrelated-tool-failure"):
            self.assertNotIn(text, out)
        self.assertIn("real-failure", self.scan("--transcript", "--session", "chosen", "--date", self.today))

    def test_chronological_limit_and_standard_roots_realpath_dedup(self):
        self.write_session("later", [self.event({"type":"function_call_output","output":"Error: later-failure"})])
        self.write_session("earlier", [self.event({"type":"function_call_output","output":"Error: earlier-failure"}, "2002-01-01T00:00:00Z")])
        standard = self.home / ".config/codex"
        standard.parent.mkdir(parents=True)
        standard.symlink_to(self.codex, target_is_directory=True)
        out = self.scan("--audit", "--days", "36500", "--limit", "1")
        self.assertEqual(out.count("later-failure"), 1)
        self.assertNotIn("earlier-failure", out)

    def test_session_alone_finds_native_errors_and_repeated_commands_count(self):
        records = []
        for n in range(2):
            stamp = (self.now + dt.timedelta(seconds=n)).isoformat()
            records += [self.event({"type":"function_call", "call_id":str(n), "name":"exec_command", "arguments":json.dumps({"cmd":"bat SKILL.md"})}, stamp),
                        self.event({"type":"function_call_output", "call_id":str(n), "output":json.dumps({"exit_code":1,"output":"permission denied reading documentation"})}, stamp)]
        self.write_session("native-only", records)
        out = self.scan("--session", "native-only")
        self.assertIn("errors=2", out)
        self.assertIn("permission denied reading documentation", out)

    def test_legacy_errors_and_cache_signals_filter_on_event_date(self):
        root = self.home / ".cache/copilot"
        root.mkdir(parents=True)
        (root / "session_chosen.log").write_text("## [2001-01-01 00:00:00] status=stdout\nCMD: old-command\nSTDOUT:\njq: parse error\n---\n")
        native = self.home / ".config/claude/projects/project/chosen.jsonl"
        native.parent.mkdir(parents=True)
        records = [{"type":"assistant","timestamp":self.stamp,"message":{"content":[{"type":"tool_use","id":"x","name":"Bash","input":{"command":"real-legacy-command"}}]}},
                   {"type":"user","timestamp":self.stamp,"message":{"content":[{"type":"tool_result","tool_use_id":"x","is_error":True,"content":"legacy-error"}]}}]
        native.write_text("\n".join(json.dumps(e) for e in records))
        out = self.scan("--audit", "--date", self.today, "--session", "chosen")
        self.assertIn("real-legacy-command", out)
        self.assertIn("legacy-error", out)
        self.assertNotIn("old-command", out)
        self.assertNotIn("jq-non-json-input", out)

    def test_native_transcript_with_hook_log_does_not_claim_missing(self):
        self.write_session("with-log", [self.event({"type":"function_call_output", "output":"Error: native-failure"})])
        root = self.home / ".cache/codex"
        root.mkdir(parents=True)
        (root / "session_with-log.log").write_text(f"## [{self.today} 12:00:00] status=stdout\nCMD: true\nSTDOUT:\nokay\n---\n")
        out = self.scan("--transcript", "--session", "with-log")
        self.assertIn("native-failure", out)
        self.assertNotIn("no transcript found", out)

    def test_classify_ignores_documentation_reads_but_keeps_real_stderr(self):
        root = self.home / ".cache/codex"
        root.mkdir(parents=True)
        (root / "session_docs.log").write_text(f"## [{self.today} 12:00:00] status=stdout\nCMD: bat SKILL.md\nSTDOUT:\njq: parse error\n---\n## [{self.today} 12:01:00] status=stderr\nCMD: bat AGENTS.md\nSTDERR:\nPermission denied\n---\n")
        out = self.scan("--classify")
        self.assertNotIn("jq-non-json-input", out)
        self.assertIn("permission-denied", out)

    def test_batched_exec_reports_each_failed_inner_result(self):
        source = 'text(await tools.exec_command({cmd:"successful-child"})); text(await tools.exec_command({cmd:"failed-child"})); text(await tools.exec_command({cmd:"other-failed-child"}));'
        result = [{"type":"text", "text":"Script completed\nWall time: 0.1 seconds\nOutput:\n" + "\n".join(json.dumps(item) for item in [
            {"exit_code":0,"output":"successful-child-output"},
            {"exit_code":2,"command":"failed-child","output":"first-inner-failure"},
            {"exit_code":3,"command":"other-failed-child","output":"second-inner-failure"}])}]
        direct = [{"type":"text","text":json.dumps({"exit_code":0,"output":"okay"})},
                  {"type":"text","text":json.dumps({"i":1,"result":{"exit_code":4,"output":"direct-list-failure"}})},
                  {"type":"text","text":json.dumps({"status":"fulfilled","value":{"exit_code":5,"output":"settled-list-failure"}})}]
        self.write_session("batch", [self.event({"type":"custom_tool_call","name":"functions.exec","call_id":"batch","input":source}),
            self.event({"type":"custom_tool_call_output","call_id":"batch","output":json.dumps(result)}),
            self.event({"type":"function_call","name":"exec","call_id":"direct","arguments":source}),
            self.event({"type":"function_call_output","call_id":"direct","output":direct})])
        out = self.scan("--audit", "--session", "batch")
        self.assertIn("errors=4", out)
        self.assertIn("child=2", out)
        self.assertIn("direct-list-failure", out)
        self.assertIn("settled-list-failure", out)
        self.assertIn("first-inner-failure", out)
        self.assertIn("second-inner-failure", out)
        self.assertIn("failed-child", out)
        self.assertIn("other-failed-child", out)
        self.assertNotIn("successful-child-output", out)

    def test_audit_ignores_readme_examples_and_keeps_failed_read(self):
        root = self.home / ".cache/codex"
        root.mkdir(parents=True)
        (root / "session_docs.log").write_text(f"## [{self.today} 12:00:00] status=stdout\nCMD: bat README.md\nSTDOUT:\njq: parse error\n---\n## [{self.today} 12:01:00] status=stderr\nCMD: bat README.md\nSTDERR:\nPermission denied\n---\n")
        out = self.scan("--audit")
        self.assertNotIn("jq-non-json-input", out)
        self.assertIn("permission-denied", out)

    def test_families_use_specific_signals_and_skip_generated_runtime_trees(self):
        root = self.home / ".cache/codex"
        root.mkdir(parents=True)
        (root / "cors_serve.py").write_text("from http.server import ThreadingHTTPServer\nprint('cors')")
        (root / "server.py").write_text("from http.server import ThreadingHTTPServer\nprint('serve')")
        for folder in ("report/trace", "playwright-report", "venv992/lib/site-packages", "test-venv311/lib", ".test_venv/lib"):
            target = root / folder
            target.mkdir(parents=True)
            (target / "index.123abc45.js").write_text("generated-" + folder + "-thread browser graphql")
            (target / "runtime.py").write_text("generated-" + folder + "-ThreadingHTTPServer")
        for folder, markers in (("review/head", (".gitignore", "package.json")), ("fetched-repo", (".git",))):
            repo = root / folder
            repo.mkdir(parents=True)
            for marker in markers:
                (repo / marker).write_text("synthetic repository marker")
            (repo / "review.ts").write_text("fetched source snapshot")
        out = self.scan("--audit")
        self.assertNotIn("github-review", out)
        self.assertNotIn("generated-", out)
        self.assertRegex(out, r"other-py\s+2")
        self.assertIn("unique=2", out)

    def test_families_archive_content_dedup_and_snapshot_exclusion(self):
        root = self.home / ".cache/codex"
        root.mkdir(parents=True)
        (root / "threads.graphql").write_text("query { viewer { login } }")
        (root / "threads-copy.graphql").write_text("query { viewer { login } }")
        (root / "threads-20261027-120000.graphql").write_text("query { timestampSnapshot }")
        (root / "threads.jq").write_text(".data.viewer.login")
        compressed = subprocess.run(["zstd", "-q", "-c"], input=b"query { repository { name } }", capture_output=True, check=True).stdout
        (root / "threads-archive.graphql.zst").write_bytes(compressed)
        generated = root / "gh-graphql-snapshots"
        generated.mkdir()
        (generated / "threads.graphql").write_text("query { ignoredSnapshot }")
        out = self.scan("--audit")
        self.assertRegex(out, r"github-review\s+3")
        self.assertNotIn("ignoredSnapshot", out)

    def test_mirrored_transcripts_survive_original_removal_without_duplicates(self):
        original = self.write_session("retained", [
            self.event({"type": "function_call_output", "output": "Error: retained-failure"}),
            self.event({"type": "message", "role": "user", "content": "retained-prompt"}),
        ])
        mirror = self.home / ".cache/copilot/agent-capture/capture/codex/sessions-source/retained.jsonl"
        mirror.parent.mkdir(parents=True)
        mirror.write_bytes(original.read_bytes())
        self.assertEqual(self.scan("--transcript", "--session", "retained").count("retained-prompt"), 1)
        original.unlink()
        out = self.scan("--transcript", "--session", "retained")
        self.assertIn("retained-failure", out)
        self.assertIn("retained-prompt", out)

    def test_cached_claude_and_copilot_messages_without_legacy_logs(self):
        base = self.home / ".cache/copilot/agent-capture/capture"
        claude = base / "claude/projects-source/project/kept-claude.jsonl"
        copilot = base / "copilot/session-state-source/kept-copilot/events.jsonl"
        for path in (claude, copilot):
            path.parent.mkdir(parents=True)
        claude.write_text(json.dumps({"type": "user", "timestamp": self.stamp, "message": {"content": "claude-kept-prompt"}}))
        copilot.write_text(json.dumps({"type": "user.message", "timestamp": self.stamp, "data": {"content": "copilot-kept-prompt"}}))
        self.assertIn("claude-kept-prompt", self.scan("--transcript", "--session", "kept-claude"))
        self.assertIn("copilot-kept-prompt", self.scan("--transcript", "--session", "kept-copilot"))

    def test_capture_internals_are_not_helper_candidates(self):
        base = self.home / ".cache/copilot/agent-capture/events/copilot/session"
        base.mkdir(parents=True)
        for name in ("captured.py", "captured-copy.py"):
            (base / name).write_text("from http.server import ThreadingHTTPServer\n" + name)
        self.assertIn("unique=0", self.scan("--audit"))

    def test_failure_hook_is_visible_before_native_transcript_flush(self):
        path = self.home / ".cache/copilot/agent-capture/events/claude/session/events.jsonl"
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({"agent": "claude", "event": "PostToolUseFailure", "session_id": "hook-only", "captured_at": self.stamp,
            "payload": {"tool_name": "Bash", "tool_input": {"command": "false"}, "error": "hook-error-before-flush"}}))
        out = self.scan("--audit", "--session", "hook-only")
        self.assertIn("CAPTURED HOOK FAILURES", out)
        self.assertIn("hook-error-before-flush", out)

if __name__ == "__main__":
    unittest.main()
