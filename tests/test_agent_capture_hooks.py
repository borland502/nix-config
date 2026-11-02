"""Managed capture hooks: passive payloads and non-destructive migration."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[1]
MERGER = ROOT / "scripts/merge-agent-capture-hooks.py"
HOOKS = ROOT / "ai-tools/hooks"


class HookTests(unittest.TestCase):
    def test_logging_failure_does_not_block_tools(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = dict(os.environ, HOME=tmp)
            for agent in ("claude", "copilot", "codex"):
                config = json.loads((HOOKS / f"{agent}-capture.json").read_text())
                event = "preToolUse" if agent == "copilot" else "PreToolUse"
                entry = config["hooks"][event][0]
                hook = entry.get("hooks", [entry])[0]
                result = subprocess.run(["/bin/sh", "-c", hook["command"]], input="{}", text=True, capture_output=True, env=env)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertTrue(result.stderr, "Capture errors must remain diagnosable")

    def test_configured_commands_capture_without_model_facing_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            executable = home / ".local/bin/ai-tools/agent-cache-capture"
            executable.parent.mkdir(parents=True)
            shutil.copyfile(ROOT / "ai-tools/scripts/agent-cache-capture", executable)
            executable.chmod(0o700)
            env = dict(os.environ, HOME=tmp, AGENT_CACHE_CAPTURE_ROOT=str(home / "capture"), AGENT_TOOLS_LIB=str(ROOT / "chezmoi/dot_local/lib"))
            for agent in ("claude", "copilot", "codex"):
                config = json.loads((HOOKS / f"{agent}-capture.json").read_text())
                for event, entries in config["hooks"].items():
                    if event.lower() not in ("sessionend", "posttooluse", "posttoolusefailure"):
                        continue
                    hook = entries[0].get("hooks", entries)[0]
                    result = subprocess.run(["/bin/sh", "-c", hook["command"]],
                        input=json.dumps({"sessionId": "fixture-session", "toolName": "Bash", "error": "fixture-error"}),
                        text=True, capture_output=True, env=env, timeout=3)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, "")
            envelopes = []
            for event_file in (home / "capture/events").glob("*/*/events.jsonl"):
                envelopes.extend(json.loads(line) for line in event_file.read_text().splitlines())
            self.assertEqual(len(envelopes), 8)
            self.assertEqual({item["agent"] for item in envelopes}, {"claude", "copilot", "codex"})

    def test_supported_passive_events_and_short_shutdown(self):
        for agent in ("claude", "copilot", "codex"):
            config = json.loads((HOOKS / f"{agent}-capture.json").read_text())
            events = config["hooks"]
            failure = "postToolUseFailure" if agent == "copilot" else "PostToolUseFailure"
            self.assertEqual(failure in events, agent != "codex")
            for event, entries in events.items():
                for entry in entries:
                    for hook in entry.get("hooks", [entry]):
                        self.assertEqual(hook["type"], "command")
                        self.assertIn(f"--agent {agent} --event {event}", hook["command"])
                        self.assertNotIn("--reconcile", hook["command"])
                        self.assertLessEqual(hook.get("timeout", hook.get("timeoutSec")), 3)

    def test_merge_preserves_user_settings_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as tmp:
            settings = Path(tmp) / "settings.json"
            unrelated = {"type": "command", "command": "echo custom"}
            old = {"type": "command", "command": 'AGENT_NAME=claude bash "$HOME/.local/bin/ai-tools/sweep-agent-assets"'}
            settings.write_text(json.dumps({"model": "custom", "hooks": {"SessionEnd": [{"hooks": [old, unrelated]}]}}))
            command = ["python3", str(MERGER), str(settings), str(HOOKS / "claude-capture.json")]
            subprocess.run(command, check=True, capture_output=True)
            first = settings.read_bytes()
            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual(first, settings.read_bytes())
            data = json.loads(first)
            self.assertEqual(data["model"], "custom")
            commands = [hook["command"] for group in data["hooks"]["SessionEnd"] for hook in group["hooks"]]
            self.assertIn("echo custom", commands)
            self.assertFalse(any("sweep-agent-assets" in cmd for cmd in commands))
            self.assertEqual(settings.stat().st_mode & 0o777, 0o600)

    def test_bad_settings_are_not_overwritten(self):
        with tempfile.TemporaryDirectory() as tmp:
            settings = Path(tmp) / "settings.json"
            for original in (b"not-json", b'{"hooks": []}'):
                settings.write_bytes(original)
                result = subprocess.run(["python3", str(MERGER), str(settings), str(HOOKS / "claude-capture.json")], capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(settings.read_bytes(), original)

    def test_codex_log_directory_default_preserves_toml_and_explicit_choice(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "config.toml"
            original = '# user comment\nmodel = "example"\n[projects."/some/project"]\ntrust_level = "trusted"\n'
            target.write_text(original)
            command = ["python3", str(MERGER), "--codex-log-dir", str(target), str(Path(tmp) / "cache logs")]
            subprocess.run(command, check=True, capture_output=True)
            first = target.read_text()
            self.assertIn(original, first)
            self.assertEqual(tomllib.loads(first)["log_dir"], str(Path(tmp) / "cache logs"))
            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual(target.read_text(), first)
            target.write_text('log_dir = "/custom/logs"\n' + original)
            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual(tomllib.loads(target.read_text())["log_dir"], "/custom/logs")
            target.write_text('invalid = [')
            result = subprocess.run(command, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(target.read_text(), 'invalid = [')


if __name__ == "__main__":
    unittest.main()
