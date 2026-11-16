import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "chezmoi/dot_local/lib/shell"
SCRIPTS = ROOT / "ai-tools/scripts"


class Hooks(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.TemporaryDirectory()
        self.addCleanup(self.home.cleanup)
        self.env = dict(
            os.environ,
            HOME=self.home.name,
            AGENT_NAME="TEST Agent!",
            AGENT_TOOLS_SHELL_LIB=str(LIB),
        )
        self.env.pop("COPILOT_HOME", None)

    def run_hook(self, name, payload):
        return subprocess.run(
            ["bash", str(SCRIPTS / name)],
            input=json.dumps(payload),
            text=True,
            capture_output=True,
            env=self.env,
            check=True,
        )

    def log(self):
        return Path(self.home.name, ".cache/testagent/session_s.log")

    def test_library_source_preserves_shell_state(self):
        script = """set -eu; trap 'true' EXIT; umask 027
before=$(set +o; trap -p; pwd; umask)
source "$AGENT_TOOLS_SHELL_LIB/agent-cache.bash"
source "$AGENT_TOOLS_SHELL_LIB/hook-log.bash"
after=$(set +o; trap -p; pwd; umask)
[[ "$before" == "$after" ]]
"""
        result = subprocess.run(
            ["bash", "-c", script], env=self.env, text=True, capture_output=True
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")

    def test_bash_payloads_and_private_mode(self):
        payload = {
            "tool_name": "Bash",
            "tool_input": {"command": "echo hi"},
            "tool_response": {"stdout": "hello", "stderr": "bad"},
            "session_id": "s",
            "cwd": "/work",
        }
        self.assertEqual(self.run_hook("log-bash.sh", payload).stdout, "")
        log = self.log().read_text()
        self.assertIn(
            "status=stderr event=bash cwd=/work\nCMD: echo hi\nSTDOUT:\nhello\nSTDERR:\nbad\n---\n",
            log,
        )
        self.assertEqual(self.log().stat().st_mode & 0o777, 0o600)
        payload = {
            "toolName": "bash",
            "toolArgs": json.dumps({"command": "pwd"}),
            "toolResult": {"interrupted": True},
            "sessionId": "s",
        }
        self.run_hook("log-bash.sh", payload)
        self.assertIn(
            "status=interrupted event=bash cwd=?\nCMD: pwd\n---\n",
            self.log().read_text(),
        )

    def test_skill_instructions_and_noop(self):
        self.run_hook(
            "log-skill.sh",
            {
                "tool_name": "Skill",
                "tool_input": {"skill": "demo", "args": "arg"},
                "tool_response": "ok",
                "session_id": "s",
            },
        )
        self.run_hook(
            "log-instructions.sh",
            {
                "hook_event_name": "InstructionsLoaded",
                "file_path": "/x",
                "reason": "start",
                "session_id": "s",
            },
        )
        before = self.log().read_text()
        self.assertIn("CMD: Skill demo arg\nSTDOUT:\nok\n---\n", before)
        self.assertIn("CMD: InstructionsLoaded reason=start file=/x\n---\n", before)
        self.run_hook("log-skill.sh", {"tool_name": "Other"})
        self.run_hook("log-instructions.sh", {"hook_event_name": "Other"})
        self.assertEqual(before, self.log().read_text())

    def test_thinking_cursor_and_redaction(self):
        transcript = Path(self.home.name, "transcript.jsonl")
        transcript.write_text(
            json.dumps(
                {
                    "message": {
                        "role": "assistant",
                        "content": [
                            {"type": "thinking", "thinking": "hello ghp_" + "a" * 25}
                        ],
                    }
                }
            )
            + "\n"
        )
        payload = {"transcript_path": str(transcript), "session_id": "s"}
        self.run_hook("log-thinking.sh", payload)
        first = self.log().read_text()
        self.assertIn("hello [REDACTED-GH-TOKEN]", first)
        self.run_hook("log-thinking.sh", payload)
        self.assertEqual(first, self.log().read_text())

    def test_truncation_boundaries(self):
        for script, payload, limit, marker in [
            (
                "log-bash.sh",
                {"tool_name": "Bash", "tool_input": {}, "session_id": "s"},
                30000,
                "[truncated 1 of 30001 chars --",
            ),
            (
                "log-skill.sh",
                {"tool_name": "Skill", "tool_input": {}, "session_id": "s"},
                8000,
                "[truncated 1 of 8001 chars —",
            ),
        ]:
            payload["tool_response"] = "x" * (limit + 1)
            self.run_hook(script, payload)
            self.assertIn(marker, self.log().read_text())

    def test_copilot_skill_and_thinking(self):
        self.run_hook(
            "log-skill.sh",
            {
                "toolName": "skill",
                "toolArgs": "{}",
                "toolResult": {"textResultForLlm": 'Skill "demo" loaded successfully.'},
                "sessionId": "s",
            },
        )
        self.assertIn("CMD: Skill demo", self.log().read_text())
        event = Path(self.home.name, ".config/copilot/session-state/s/events.jsonl")
        event.parent.mkdir(parents=True)
        event.write_text(
            json.dumps(
                {"type": "assistant.message", "data": {"reasoningText": "thought"}}
            )
            + "\n"
        )
        self.run_hook("log-thinking.sh", {"sessionId": "s"})
        self.assertIn("STDOUT:\nthought\n---", self.log().read_text())

    def test_relocated_hook_and_installed_bin_layout(self):
        relocated = Path(self.home.name, "store/script")
        relocated.parent.mkdir()
        shutil.copy(SCRIPTS / "log-bash.sh", relocated)
        subprocess.run(
            ["bash", str(relocated)],
            input=json.dumps({"tool_name": "Bash", "session_id": "s"}),
            text=True,
            env=self.env,
            check=True,
            capture_output=True,
        )
        self.assertIn("event=bash", self.log().read_text())
        local = Path(self.home.name, "local")
        (local / "bin").mkdir(parents=True)
        shutil.copytree(LIB, local / "lib/shell")
        exe = local / "bin/gh-run-logs"
        shutil.copy(ROOT / "chezmoi/dot_local/bin/executable_gh-run-logs", exe)
        fake = local / "bin/gh"
        fake.write_text('#!/bin/sh\nprintf "fixture\\n"\n')
        fake.chmod(0o755)
        env = dict(self.env, PATH=str(local / "bin") + os.pathsep + self.env["PATH"])
        env.pop("AGENT_TOOLS_SHELL_LIB")
        result = subprocess.run(
            ["bash", str(exe), "123", "--tail", "0"],
            env=env,
            text=True,
            capture_output=True,
            check=True,
        )
        self.assertIn("run-123-failed.log", result.stdout)
        self.assertEqual(
            Path(self.home.name, ".cache/testagent/run-123-failed.log").read_text(),
            "fixture\n",
        )

    def test_bash_noise_and_exact_boundary(self):
        payload = {
            "tool_name": "Bash",
            "tool_input": {},
            "tool_response": {
                "stdout": "x" * 30000,
                "stderr": "Shell cwd was reset to /tmp\nbroken pipe",
            },
            "session_id": "s",
        }
        self.run_hook("log-bash.sh", payload)
        text = self.log().read_text()
        self.assertIn("status=ok", text)
        self.assertNotIn("STDERR:", text)
        self.assertNotIn("[truncated", text)

    def test_thinking_truncation_and_cache_alias(self):
        shared = Path(self.home.name, ".cache/shared")
        shared.mkdir(parents=True)
        Path(self.home.name, ".cache/testagent").symlink_to(
            shared, target_is_directory=True
        )
        transcript = Path(self.home.name, "transcript.jsonl")
        transcript.write_text(
            json.dumps(
                {
                    "message": {
                        "role": "assistant",
                        "content": [{"type": "thinking", "thinking": "x" * 20001}],
                    }
                }
            )
            + "\n"
        )
        self.run_hook(
            "log-thinking.sh", {"transcript_path": str(transcript), "session_id": "s"}
        )
        self.assertIn(
            "x" * 20000 + "\n... [thinking truncated; see transcript for full text]",
            (shared / "session_s.log").read_text(),
        )

    def test_compressor_honors_explicit_cache_directory(self):
        cache = Path(self.home.name, "custom")
        cache.mkdir()
        env = dict(
            self.env, CACHE_DIR=str(cache), COMPRESS_OLD_CACHE_MIN_INTERVAL_SEC="0"
        )
        subprocess.run(
            ["bash", str(SCRIPTS / "compress-old-cache")],
            env=env,
            capture_output=True,
            text=True,
            check=True,
        )
        self.assertTrue((cache / ".compress-old-cache.last_run").exists())


if __name__ == "__main__":
    unittest.main()
