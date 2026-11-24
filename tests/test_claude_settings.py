import json
import importlib.util
from unittest import mock
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/reconcile-claude-settings.py"
MANIFEST = ROOT / "ai-tools/hooks/claude-capture.json"


class ClaudeSettingsTests(unittest.TestCase):
    def run_helper(self, target):
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(target), str(MANIFEST)],
            capture_output=True,
        )

    def test_empty_and_custom_hooks_are_preserved_and_managed_hooks_added(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "settings.json"
            original = {
                "custom": {"nested": [1, 2]},
                "hooks": {
                    "PostToolUse": [
                        {"matcher": "Bash", "hooks": [{"command": "my-custom-hook"}]}
                    ]
                },
            }
            target.write_text(json.dumps(original))
            result = self.run_helper(target)
            self.assertEqual(result.returncode, 0, result.stderr)
            settings = json.loads(target.read_text())
            self.assertEqual(settings["custom"], original["custom"])
            commands = [
                h["command"]
                for g in settings["hooks"]["PostToolUse"]
                for h in g["hooks"]
            ]
            self.assertIn("my-custom-hook", commands)
            self.assertTrue(any("log-bash.sh" in c for c in commands))
            before = target.read_bytes()
            self.assertEqual(self.run_helper(target).returncode, 0)
            self.assertEqual(target.read_bytes(), before)

    def test_legacy_migrations(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "settings.json"
            target.write_text(
                json.dumps(
                    {
                        "model": "claude-old",
                        "env": {"ANTHROPIC_DEFAULT_OPUS_MODEL": "old", "OTHER": "x"},
                        "hooks": {
                            "Stop": [
                                {
                                    "hooks": [
                                        {"command": "$HOME/.local/bin/log-thinking.sh"},
                                        {
                                            "command": "$HOME/.local/bin/compress-old-cache"
                                        },
                                    ]
                                }
                            ]
                        },
                    }
                )
            )
            result = self.run_helper(target)
            self.assertEqual(result.returncode, 0, result.stderr)
            data = json.loads(target.read_text())
            self.assertEqual(data["model"], "opus")
            self.assertEqual(data["env"], {"OTHER": "x"})
            commands = [h for g in data["hooks"]["Stop"] for h in g["hooks"]]
            self.assertFalse(any("log-thinking" in h["command"] for h in commands))
            self.assertTrue(
                any(
                    "/ai-tools/compress-old-cache" in h["command"] and h["async"]
                    for h in commands
                )
            )

    def test_malformed_settings_remain_untouched(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "settings.json"
            target.write_bytes(b"{broken")
            self.assertNotEqual(self.run_helper(target).returncode, 0)
            self.assertEqual(target.read_bytes(), b"{broken")

    def test_concurrent_edit_is_not_overwritten(self):
        spec = importlib.util.spec_from_file_location("claude_reconcile_test", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        real_atomic = module.atomic_output

        def intercept(target, **kwargs):
            check = kwargs["before_publish"]

            def modify_then_check():
                target.write_text('{"concurrent": true}')
                check()

            kwargs["before_publish"] = modify_then_check
            return real_atomic(target, **kwargs)

        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "settings.json"
            target.write_text("{}")
            with (
                mock.patch.object(module, "atomic_output", intercept),
                mock.patch.object(
                    sys, "argv", [str(SCRIPT), str(target), str(MANIFEST)]
                ),
            ):
                with self.assertRaisesRegex(ValueError, "changed during"):
                    module.main()
            self.assertEqual(json.loads(target.read_text()), {"concurrent": True})

    def test_custom_marker_collisions_do_not_suppress_managed_hooks(self):
        cases = [
            ("PostToolUse", "Edit", "log-bash.sh", "Bash"),
            ("PostToolUse", "Other", "log-skill.sh", "Skill"),
            ("InstructionsLoaded", None, "log-instructions.sh", None),
            ("SessionEnd", None, "claude-cache-stats", None),
            ("PreToolUse", "Other", "bash-habits-hint", "Bash"),
            ("PostToolUse", "Other", "format-on-edit", "Edit|Write|MultiEdit"),
        ]
        for event, custom_matcher, script, expected_matcher in cases:
            with self.subTest(script=script), tempfile.TemporaryDirectory() as tmp:
                target = Path(tmp) / "settings.json"
                group = {"hooks": [{"command": "/custom/" + script}]}
                if custom_matcher is not None:
                    group["matcher"] = custom_matcher
                groups_in = [group]
                if custom_matcher is not None:
                    groups_in.append(
                        {
                            "matcher": custom_matcher,
                            "hooks": [
                                {"command": "$HOME/.local/bin/ai-tools/" + script}
                            ],
                        }
                    )
                target.write_text(json.dumps({"hooks": {event: groups_in}}))
                self.assertEqual(self.run_helper(target).returncode, 0)
                groups = json.loads(target.read_text())["hooks"][event]
                self.assertIn(group, groups)
                self.assertTrue(
                    any(
                        g.get("matcher") == expected_matcher
                        and any(
                            "$HOME/.local/bin/ai-tools/" + script
                            in h.get("command", "")
                            for h in g["hooks"]
                        )
                        for g in groups
                    )
                )

    def test_argument_collision_and_valid_managed_commands(self):
        path = "$HOME/.local/bin/ai-tools/log-bash.sh"
        cases = [
            (f"printf '%s' \"{path}\"", False),
            (f'"{path}"', True),
            (f'AGENT_NAME=claude bash "{path}"', True),
            (f'env AGENT_NAME=claude /bin/bash "{path}"', True),
            (f'env AGENT_NAME=claude "{path}"', True),
        ]
        for command, managed in cases:
            with self.subTest(command=command), tempfile.TemporaryDirectory() as tmp:
                target = Path(tmp) / "settings.json"
                group = {"matcher": "Bash", "hooks": [{"command": command}]}
                target.write_text(json.dumps({"hooks": {"PostToolUse": [group]}}))
                self.assertEqual(self.run_helper(target).returncode, 0)
                groups = json.loads(target.read_text())["hooks"]["PostToolUse"]
                self.assertIn(group, groups)
                bash_groups = [g for g in groups if g.get("matcher") == "Bash"]
                self.assertEqual(len(bash_groups), 1 if managed else 2)
                first = target.read_bytes()
                self.assertEqual(self.run_helper(target).returncode, 0)
                self.assertEqual(target.read_bytes(), first)

    def test_attribution_jq_truthiness(self):
        for value in ({}, [], "", 0, False, None):
            with self.subTest(value=value), tempfile.TemporaryDirectory() as tmp:
                target = Path(tmp) / "settings.json"
                target.write_text(json.dumps({"attribution": value}))
                self.assertEqual(self.run_helper(target).returncode, 0)
                expected = (
                    {"commit": "", "pr": ""}
                    if value is False or value is None
                    else value
                )
                self.assertEqual(
                    json.loads(target.read_text())["attribution"], expected
                )

    def test_noop_restores_private_permissions_without_rewriting(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "settings.json"
            self.assertEqual(self.run_helper(target).returncode, 0)
            before = target.read_bytes()
            target.chmod(0o644)
            self.assertEqual(self.run_helper(target).returncode, 0)
            self.assertEqual(target.read_bytes(), before)
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
