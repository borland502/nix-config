"""Offline contracts for the reusable AWS log tools."""
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "chezmoi/dot_local/bin"


class LogTools(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.dir = Path(self.temp.name)
        self.calls = self.dir / "calls"
        self.kac = self.dir / "kac"
        self.kac.write_text('printf "kac\\n" >> "$CALLS"\nreturn "${KAC_RC:-0}"\n')
        self.aws = self.dir / "aws"
        self.aws.write_text("#!/usr/bin/env python3\nimport json,os,sys\nwith open(os.environ['CALLS'],'a') as f: f.write(json.dumps(sys.argv[1:])+'\\n')\nprint(os.environ.get('AWS_JSON', json.dumps(dict(events=[]))))\nsys.exit(int(os.environ.get('AWS_RC', '0')))\n")
        self.aws.chmod(0o700)
        self.env = dict(os.environ, KAC_PATH=str(self.kac), AWS_BIN=str(self.aws), CALLS=str(self.calls))

    def run_tool(self, name, *args, **env):
        script = BIN / ("executable_" + name)
        self.assertTrue(script.exists(), f"Missing tool: {name}")
        return subprocess.run([sys.executable, str(script), *map(str, args)], env=dict(self.env, **env), capture_output=True, text=True)

    def fetch(self, *extra, **env):
        return self.run_tool("aws-log-fetch", "/test/group", "--start", "2026-10-01T00:00:00Z", "--end", "2026-10-01T01:00:00+00:00", "--output", self.dir / "events.json", *extra, **env)

    def metrics(self, content, *args):
        source = self.dir / "input"
        source.write_text(content)
        return self.run_tool("aws-lambda-metrics", source, *args)

    def test_fetch_capture_private_complete_json(self):
        payload = {"events": [{"message": "hello"}, {"message": "world"}], "searchedLogStreams": []}
        result = self.fetch("--region", "test-region", "--request-id", "req-123", AWS_JSON=json.dumps(payload))
        self.assertEqual(result.returncode, 0, result.stderr)
        target = self.dir / "events.json"
        self.assertEqual(result.stdout.strip(), str(target))
        self.assertEqual(json.loads(target.read_text()), payload)
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)
        calls = self.calls.read_text().splitlines()
        self.assertEqual(calls[0], "kac")
        args = json.loads(calls[1])
        self.assertEqual(args[:2], ["logs", "filter-log-events"])
        self.assertNotIn("--no-paginate", args)
        self.assertEqual(args[args.index("--filter-pattern") + 1], '"req-123"')
        self.assertEqual(args[args.index("--start-time") + 1], "1790812800000")

    def test_help_never_loads_credentials(self):
        for name in ("aws-log-fetch", "aws-lambda-metrics"):
            result = self.run_tool(name, "--help")
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.calls.exists())

    def test_bad_inputs_fail_before_credentials(self):
        for args in [("--start", "2026-10-01T00:00:00"), ("--end", "2026-09-01T00:00:00Z"), ("--start", "garbage"), ("--request-id", 'bad"id'), ("--start", "1960-01-01T00:00:00Z")]:
            with self.subTest(args=args):
                self.assertNotEqual(self.fetch(*args).returncode, 0)
                self.assertFalse(self.calls.exists())

    def test_failed_credentials_prevent_aws(self):
        result = self.fetch(KAC_RC="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls.read_text(), "kac\n")
        self.assertFalse((self.dir / "events.json").exists())

    def test_failure_preserves_output(self):
        target = self.dir / "events.json"
        target.write_text("original")
        for env in ({"AWS_RC": "9"}, {"AWS_JSON": "not-json"}, {"AWS_JSON": "{}"}):
            with self.subTest(env=env):
                result = self.fetch("--force", **env)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(target.read_text(), "original")
                self.assertEqual(result.stdout, "")
        self.assertEqual(sorted(p.name for p in self.dir.iterdir() if p.name.startswith(".events")), [])

    def test_no_clobber_and_explicit_force(self):
        target = self.dir / "events.json"
        target.write_text("original")
        self.assertNotEqual(self.fetch().returncode, 0)
        self.assertFalse(self.calls.exists())
        self.assertEqual(self.fetch("--force").returncode, 0)

    def test_text_report_fields_are_independent(self):
        result = self.metrics("REPORT RequestId: abc Duration: 12.34 ms Billed Duration: 100 ms Memory Size: 128 MB Max Memory Used: 91 MB Init Duration: 24.5 ms Status: success\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), [{"requestId": "abc", "durationMs": 12.34, "billedDurationMs": 100, "memorySizeMB": 128, "maxMemoryUsedMB": 91, "initDurationMs": 24.5, "status": "success"}])

    def test_partial_timeout_does_not_reuse_billed_or_init_duration(self):
        result = self.metrics("REPORT RequestId: timeout Billed Duration: 300 ms Init Duration: 42 ms Status: timeout\n")
        record = json.loads(result.stdout)[0]
        self.assertIsNone(record["durationMs"])
        self.assertIsNone(record["memorySizeMB"])
        self.assertEqual(record["status"], "timeout")

    def test_structured_reports_in_events_and_json_lines(self):
        report = {"type": "platform.report", "record": {"requestId": "structured", "metrics": {"durationMs": 5, "billedDurationMs": 10, "memorySizeMB": 256, "maxMemoryUsedMB": 100, "initDurationMs": 2}, "status": "success"}}
        contents = [json.dumps(report) + "\n" + json.dumps({"type": "platform.start"}), json.dumps({"events": [{"message": json.dumps(report)}, {"message": "unrelated"}]})]
        for content in contents:
            with self.subTest(content=content):
                result = self.metrics(content)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout)[0]["requestId"], "structured")
                self.assertEqual(json.loads(result.stdout)[0]["durationMs"], 5)

    def test_malformed_claimed_json_fails(self):
        for content in ('{"events":', '{"events": [{"message": "{bad"}]}', '{"type":"platform.start"}\n{bad'):
            with self.subTest(content=content):
                self.assertNotEqual(self.metrics(content).returncode, 0)

    def test_mixed_lines_parse_structured_reports_and_reject_bad_json(self):
        report = {"type": "platform.report", "record": {"requestId": "partial", "status": "timeout"}}
        result = self.metrics("ordinary message\n" + json.dumps(report))
        self.assertEqual(result.returncode, 0, result.stderr)
        records = json.loads(result.stdout)
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]["status"], "timeout")
        self.assertIsNone(records[0]["durationMs"])
        self.assertNotEqual(self.metrics("ordinary message\n{bad").returncode, 0)

    def test_metrics_parse_failure_preserves_previous_output(self):
        target = self.dir / "metrics.json"
        target.write_text("original")
        result = self.metrics('{bad', "--output", target)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(target.read_text(), "original")

    def test_bracket_prefixed_raw_messages_do_not_hide_reports(self):
        result = self.metrics("[INFO] request started\nREPORT RequestId: raw Duration: 2 ms\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)[0]["requestId"], "raw")

    def test_bracket_prefixed_event_messages_do_not_hide_reports(self):
        payload = {"events": [{"message": "[INFO] request started"}, {"message": "REPORT RequestId: event Duration: 3 ms"}]}
        result = self.metrics(json.dumps(payload))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)[0]["requestId"], "event")

    def test_malformed_structured_arrays_still_fail(self):
        for content in ('[{"type": "platform.report"}', '[invalid]', '[INFO] request started\n[{"type":'):
            with self.subTest(content=content):
                self.assertNotEqual(self.metrics(content).returncode, 0)

    def test_no_reports_and_private_output(self):
        self.assertEqual(json.loads(self.metrics("ordinary message\n").stdout), [])
        target = self.dir / "metrics.json"
        result = self.metrics(json.dumps(dict(events=[])), "--output", target)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(target.read_text()), [])
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)


if __name__ == "__main__":
    unittest.main()
