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

    def test_overlap_with_proven_call_identity_and_identical_retries_all_modes(self):
        records = []
        for cid in ("one", "two"):
            records += [
                self.event(
                    {
                        "type": "function_call",
                        "name": "exec_command",
                        "call_id": cid,
                        "arguments": {"cmd": "false retry"},
                    }
                ),
                self.event(
                    {
                        "type": "function_call_output",
                        "call_id": cid,
                        "output": {"exit_code": 1, "output": "retry failure"},
                    }
                ),
                self.event(
                    {
                        "type": "item_completed",
                        "item": {
                            "type": "CommandExecution",
                            "call_id": cid,
                            "command": "false retry",
                            "exit_code": 1,
                            "aggregated_output": "retry failure",
                        },
                    }
                ),
            ]
        self.write_session("overlap", records)
        for mode in ((), ("--audit",), ("--classify",), ("--transcript",)):
            with self.subTest(mode=mode):
                out = self.scan(*mode, "--session", "overlap")
                self.assertIn("errors=2", out)

    def test_status_ok_documentation_is_not_a_failure_in_any_mode(self):
        root = self.home / ".cache/codex"
        root.mkdir(parents=True)
        (root / "session_docs.log").write_text(
            f"## [{self.today} 12:00:00] status=ok\nCMD: bat README.md\nSTDOUT:\njq: parse error\nExpiredToken\n---\n"
        )
        for mode in ((), ("--audit",), ("--classify",)):
            with self.subTest(mode=mode):
                out = self.scan(*mode)
                self.assertNotIn("jq-non-json-input", out)
                self.assertNotIn("expired-token", out)
                self.assertNotIn("stale-aws-creds", out)

    def test_json_evidence_retains_full_output_locators_and_ambiguous_observations(
        self,
    ):
        output = (
            "boilerplate\n" * 100 + "Permission denied: useful error after boilerplate"
        )
        self.write_session(
            "uncertain",
            [
                self.event(
                    {
                        "type": "function_call_output",
                        "output": {"exit_code": 1, "output": output},
                    }
                ),
                self.event(
                    {
                        "type": "item_completed",
                        "item": {
                            "type": "CommandExecution",
                            "command": "",
                            "exit_code": 1,
                            "aggregated_output": output,
                        },
                    }
                ),
            ],
        )
        data = json.loads(self.scan("--json", "--session", "uncertain"))
        self.assertEqual(data["error_observations"], 2)
        self.assertIsNone(data["unique_executions"])
        self.assertEqual(len(data["events"]), 2)
        for event in data["events"]:
            self.assertEqual(event["output"], output)
            self.assertIn("Permission denied", event["excerpt"])
            self.assertTrue(event["sources"][0]["line"])
            self.assertTrue(event["sources"][0]["path"].endswith(".jsonl"))

    def test_index_hits_append_rotation_corruption_and_unavailable_directory(self):
        source = self.write_session(
            "indexed",
            [
                self.event(
                    {
                        "type": "function_call",
                        "name": "exec_command",
                        "call_id": "x",
                        "arguments": {"cmd": "original-command"},
                    }
                )
            ],
        )
        first = json.loads(self.scan("--json", "--session", "indexed"))
        second = json.loads(self.scan("--json", "--session", "indexed"))
        self.assertEqual(first["index"]["parsed_sources"], 1)
        self.assertEqual(second["index"]["parsed_sources"], 0)
        with source.open("a") as stream:
            stream.write(
                "\n"
                + json.dumps(
                    self.event(
                        {
                            "type": "function_call_output",
                            "call_id": "x",
                            "output": {"exit_code": 1, "output": "appended-failure"},
                        }
                    )
                )
            )
        appended = json.loads(self.scan("--json", "--session", "indexed"))
        self.assertEqual(appended["events"][0]["command"], "original-command")
        self.assertEqual(appended["index"]["parsed_sources"], 1)
        source.write_text(
            json.dumps(
                self.event(
                    {
                        "type": "function_call_output",
                        "output": "Error: replacement-failure",
                    }
                )
            )
        )
        replaced = json.loads(self.scan("--json", "--session", "indexed"))
        self.assertEqual(replaced["error_observations"], 1)
        self.assertIn("replacement-failure", replaced["events"][0]["output"])
        index = Path(replaced["index"]["path"])
        index.write_text("{broken")
        self.assertEqual(
            json.loads(self.scan("--json", "--session", "indexed"))[
                "error_observations"
            ],
            1,
        )
        index.unlink()
        index.parent.rmdir()
        index.parent.write_text("index directory unavailable")
        self.assertEqual(
            json.loads(self.scan("--json", "--session", "indexed"))[
                "error_observations"
            ],
            1,
        )

    def test_two_identical_missing_id_failures_remain_two_observations(self):
        self.write_session(
            "missing-ids",
            [
                self.event(
                    {
                        "type": "function_call_output",
                        "output": {"exit_code": 1, "output": "same failure"},
                    }
                )
            ]
            * 2,
        )
        out = self.scan("--audit", "--session", "missing-ids")
        self.assertIn("errors=2", out)

    def test_stale_mirror_prefix_and_disappearing_sources_with_index(self):
        output = self.event(
            {
                "type": "function_call_output",
                "output": {"exit_code": 1, "output": "mirrored failure"},
            }
        )
        original = self.write_session("mirror-index", [output])
        mirror = (
            self.home
            / ".cache/copilot/agent-capture/capture/codex/sessions-source/mirror-index.jsonl"
        )
        mirror.parent.mkdir(parents=True)
        mirror.write_bytes(original.read_bytes())
        self.assertEqual(
            json.loads(self.scan("--json", "--session", "mirror-index"))[
                "error_observations"
            ],
            1,
        )
        with original.open("a") as stream:
            stream.write("\n" + json.dumps(output))
        self.assertEqual(
            json.loads(self.scan("--json", "--session", "mirror-index"))[
                "error_observations"
            ],
            2,
        )
        original.unlink()
        data = json.loads(self.scan("--json", "--session", "mirror-index"))
        self.assertEqual(data["error_observations"], 1)
        self.assertEqual(data["index"]["parsed_sources"], 0)
        mirror.unlink()
        self.assertEqual(
            json.loads(self.scan("--json", "--session", "mirror-index"))[
                "error_observations"
            ],
            0,
        )

    def test_original_overlap_without_relationship_is_honestly_uncertain(self):
        self.write_session(
            "unlinked",
            [
                self.event(
                    {
                        "type": "function_call",
                        "name": "functions.exec",
                        "call_id": "outer",
                        "arguments": "text(await tools.exec_command(...))",
                    }
                ),
                self.event(
                    {
                        "type": "function_call_output",
                        "call_id": "outer",
                        "output": {"exit_code": 1, "output": "actual failure"},
                    }
                ),
                self.event(
                    {
                        "type": "item_completed",
                        "item": {
                            "type": "CommandExecution",
                            "command": "false",
                            "exit_code": 1,
                            "aggregated_output": "actual failure",
                        },
                    }
                ),
            ],
        )
        data = json.loads(self.scan("--json", "--session", "unlinked"))
        self.assertEqual(data["error_observations"], 2)
        self.assertEqual(data["ambiguous_observations"], 2)
        self.assertIsNone(data["unique_executions"])
        self.assertIn(
            "unique_executions=unknown", self.scan("--audit", "--session", "unlinked")
        )

    def test_schema_replacement_and_evidence_alias(self):
        source = self.write_session(
            "schema",
            [
                self.event(
                    {"type": "function_call_output", "output": "Error: before rotation"}
                )
            ],
        )
        data = json.loads(self.scan("--json", "--session", "schema"))
        index = Path(data["index"]["path"])
        content = json.loads(index.read_text())
        content["schema"] = -1
        index.write_text(json.dumps(content))
        self.assertEqual(
            json.loads(self.scan("--evidence", "--session", "schema"))["index"][
                "parsed_sources"
            ],
            1,
        )
        replacement = source.with_suffix(".new")
        replacement.write_text(
            json.dumps(
                self.event(
                    {"type": "function_call_output", "output": "Error: after rotation"}
                )
            )
        )
        replacement.replace(source)
        data = json.loads(self.scan("--json", "--session", "schema"))
        self.assertEqual(data["error_observations"], 1)
        self.assertEqual(data["events"][0]["output"], "Error: after rotation")

    def test_classify_preserves_retained_session_window_and_categories(self):
        root = self.home / ".cache/copilot"
        root.mkdir(parents=True)
        (root / "session_retained-category.log").write_text(
            "## [2001-01-01 12:00:00] status=stderr\nCMD: psql fixture\nSTDERR:\ncould not connect to server\n---\n"
        )
        out = self.scan("--classify", "--session", "retained-category")
        self.assertIn("db-docker-conn", out)

    def test_failed_read_native_and_hook_string_arguments_keep_locators(self):
        root = self.home / ".cache/copilot/agent-capture/events/copilot/hook-args"
        root.mkdir(parents=True)
        (root / "events.jsonl").write_text(
            json.dumps(
                {
                    "event": "PostToolUseFailure",
                    "session_id": "hook-args",
                    "agent": "copilot",
                    "captured_at": self.stamp,
                    "payload": {
                        "toolName": "Bash",
                        "toolArgs": json.dumps({"command": "bat README.md"}),
                        "error": "Permission denied",
                    },
                }
            )
        )
        data = json.loads(self.scan("--json", "--session", "hook-args"))
        self.assertEqual(data["hook_observations"][0]["command"], "bat README.md")
        self.assertTrue(data["hook_observations"][0]["sources"][0]["line"])

    def test_semantically_corrupt_index_falls_back_to_source(self):
        self.write_session("bad-index", [self.event({"type":"function_call_output", "output":"Error: valid source"})])
        result = json.loads(self.scan("--json", "--session", "bad-index"))
        index = Path(result["index"]["path"])
        saved = json.loads(index.read_text())
        next(iter(saved["sources"].values()))["events"][0]["session"] = 123
        index.write_text(json.dumps(saved))
        result = json.loads(self.scan("--json", "--session", "bad-index"))
        self.assertEqual(result["error_observations"], 1)
        self.assertEqual(result["index"]["parsed_sources"], 1)

    def test_explicit_batch_child_identity_reconciles_command_items_and_keeps_retries(self):
        children = [{"call_id":cid, "exit_code":1, "command":"false identical", "output":"identical failure"}
                    for cid in ("child-a", "child-b")]
        records = [self.event({"type":"function_call", "call_id":"outer", "name":"functions.exec", "arguments":"batch fixture"}),
                   self.event({"type":"function_call_output", "call_id":"outer", "output":children})]
        for child in children:
            records.append(self.event({"type":"item_completed", "item":{"type":"CommandExecution", "call_id":child["call_id"],
                "command":child["command"], "exit_code":1, "aggregated_output":child["output"]}}))
        records.extend([self.event({"type":"function_call", "call_id":"retry-c", "name":"exec_command", "arguments":{"cmd":"false identical"}}),
                        self.event({"type":"function_call_output", "call_id":"retry-c", "output":{"exit_code":1, "output":"identical failure"}})])
        self.write_session("batch-identity", records)
        for attempt in range(2):
            data = json.loads(self.scan("--json", "--session", "batch-identity"))
            self.assertEqual(data["error_observations"], 3)
            self.assertEqual(data["unique_executions"], 3)
            by_id = {event["call_id"]:event for event in data["events"]}
            self.assertEqual(set(by_id), {"child-a", "child-b", "retry-c"})
            self.assertEqual(len(by_id["child-a"]["sources"]), 2)
            self.assertEqual(len(by_id["child-b"]["sources"]), 2)
            self.assertEqual(data["index"]["parsed_sources"], 1 if attempt == 0 else 0)

    def test_nonfinite_or_unrenderable_index_timestamps_reparse_source(self):
        self.write_session("timestamp-index", [self.event({"type":"function_call_output", "output":"Error: usable timestamp"})])
        data = json.loads(self.scan("--json", "--session", "timestamp-index"))
        index = Path(data["index"]["path"])
        saved = json.loads(index.read_text())
        for stamp in (float("nan"), float("inf"), float("-inf"), 1e300, -1e300, 253402300800, 10**1000):
            for mode in ("--json", "--audit"):
                with self.subTest(stamp=repr(stamp)[:30], mode=mode):
                    next(iter(saved["sources"].values()))["events"][0]["timestamp"] = stamp
                    index.write_text(json.dumps(saved))
                    output = self.scan(mode, "--session", "timestamp-index", "--date", self.today)
                    if mode == "--json":
                        data = json.loads(output)
                        self.assertEqual(data["error_observations"], 1)
                        self.assertEqual(data["index"]["parsed_sources"], 1)
                    else:
                        self.assertIn("usable timestamp", output)

    def test_prior_identity_index_schema_is_reparsed(self):
        self.write_session("old-schema", [self.event({"type":"function_call_output", "output":"Error: current source"})])
        data = json.loads(self.scan("--json", "--session", "old-schema"))
        index = Path(data["index"]["path"])
        saved = json.loads(index.read_text())
        saved["schema"] = 1
        index.write_text(json.dumps(saved))
        self.assertEqual(json.loads(self.scan("--json", "--session", "old-schema"))["index"]["parsed_sources"], 1)

    def test_machine_evidence_caps_each_array_and_reports_omissions(self):
        records, hooks, logs = [], [], []
        # Write newest first so selection must follow timestamps, not file order.
        for number in (2, 0, 1):
            stamp = (self.now - dt.timedelta(minutes=3 - number)).isoformat()
            output = f"Permission denied: record-{number} " + "x" * 3000
            command = f"probe-{number} " + "y" * 3000
            records.append(self.event({"type": "item_completed", "item": {
                "type": "CommandExecution", "command": command,
                "exit_code": 1, "aggregated_output": output,
            }}, stamp))
            hooks.append({"event": "PostToolUseFailure", "session_id": "array-cap",
                          "agent": "codex", "captured_at": stamp,
                          "payload": {"tool_name": "Bash", "error": output,
                                      "tool_input": {"command": command}}})
            logs.append(f"## [{stamp}] status=stderr\nCMD: {command}\nSTDERR:\n{output}\n---\n")
        native = self.write_session("array-cap", records)
        hook = self.home / ".cache/copilot/agent-capture/events/codex/array-cap/events.jsonl"
        log = self.home / ".cache/codex/session_array-cap.log"
        for source in (hook, log):
            source.parent.mkdir(parents=True, exist_ok=True)
        hook.write_text("\n".join(json.dumps(row) for row in hooks))
        log.write_text("".join(logs))
        originals = {source: source.read_bytes() for source in (native, hook, log)}
        for alias in ("--json", "--evidence"):
            for limit in (0, 1):
                for full in (False, True):
                    with self.subTest(alias=alias, limit=limit, full=full):
                        flags = [alias, "--limit", str(limit), "--session", "array-cap", "--date", self.today]
                        if full:
                            flags.append("--full-output")
                        data = json.loads(self.scan(*flags))
                        self.assertEqual(data["error_observations"], 3)
                        for key in ("events", "hook_observations", "heuristic_signals"):
                            self.assertEqual(len(data[key]), limit, key)
                        self.assertIn("record_counts", data)
                        for key in ("events", "hook_observations", "heuristic_signals"):
                            self.assertEqual(data["record_counts"][key], {
                                "total": 3, "selected": limit, "omitted": 3 - limit,
                            })
                            for row in data[key]:
                                self.assertIn("record-2", row["output"])
                                self.assertIn("probe-2", row["command"])
                                for field in ("output", "command"):
                                    self.assertGreater(row[field + "_chars"], 2000)
                                    self.assertEqual(row[field + "_truncated"], not full)
                                    self.assertEqual(len(row[field]), row[field + "_chars"] if full else 2000)
                                self.assertTrue(row["sources"][0]["path"])
                                self.assertGreater(row["sources"][0]["line"], 0)
                        self.assertEqual(data["record_limit"], limit)
        for source, original in originals.items():
            self.assertEqual(source.read_bytes(), original)
        index = json.loads(Path(data["index"]["path"]).read_text())
        indexed = next(iter(index["sources"].values()))["events"]
        self.assertEqual(len(indexed), 3)
        self.assertTrue(all(len(row["output"]) > 2000 for row in indexed))

    def test_evidence_output_is_bounded_with_explicit_full_output_opt_in(self):
        output = "ordinary boilerplate\n" * 2000 + "Permission denied: meaningful failure at end"
        self.write_session("bounded-evidence", [self.event({"type":"function_call_output", "output":{"exit_code":1, "output":output}})])
        bounded = json.loads(self.scan("--json", "--session", "bounded-evidence"))["events"][0]
        self.assertLessEqual(len(bounded["output"]), 2000)
        self.assertTrue(bounded["output_truncated"])
        self.assertEqual(bounded["output_chars"], len(output))
        self.assertIn("Permission denied", bounded["excerpt"])
        self.assertTrue(bounded["sources"][0]["path"].endswith(".jsonl"))
        self.assertGreater(bounded["sources"][0]["line"], 0)
        full = json.loads(self.scan("--json", "--full-output", "--session", "bounded-evidence"))["events"][0]
        self.assertEqual(full["output"], output)
        self.assertFalse(full["output_truncated"])
        self.assertEqual(full["sources"], bounded["sources"])

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
