"""Serena setup must preserve mutable agent configuration."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/configure-agent-mcp.py"


class SerenaConfigTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.directory = Path(directory.name)
        self.command = str(self.directory / "home with spaces/.local/bin/serena-mcp")

    def invoke(self, mode, target, manifest):
        manifest_path = self.directory / "manifest.json"
        manifest_path.write_text(manifest)
        return subprocess.run([sys.executable, str(SCRIPT), mode, str(target), str(manifest_path)], capture_output=True, text=True)

    def run_config(self, mode, target):
        return self.invoke(mode, target, json.dumps({"serena": ({"type": "stdio", "command": self.command, "args": ["--context", "claude-code"]} if mode == "claude" else {"command": self.command, "args": ["--context", "codex"], "startup_timeout_sec": 120, "tool_timeout_sec": 120})}))

    def test_codex_inline_server_tables_preserve_other_settings(self):
        samples = (
            '# empty\nmcp_servers = {} # keep\n',
            "note = '''mcp_servers = { fake = {} }'''\n\"mcp_servers\" = { custom = { command = \"mine\" } } # keep\n",
        )
        for original in samples:
            with self.subTest(original=original):
                target = self.directory / "inline.toml"
                target.write_text(original)
                before = tomllib.loads(original)
                result = self.invoke("codex", target, json.dumps({"custom": {"command": "different"}, "remote": {"url": "https://example.org/mcp"}}))
                self.assertEqual(result.returncode, 0, result.stderr)
                after = tomllib.loads(target.read_text())
                self.assertIn("# keep", target.read_text())
                self.assertEqual(after.get("note"), before.get("note"))
                self.assertEqual(after["mcp_servers"]["remote"]["url"], "https://example.org/mcp")
                if "custom" in before["mcp_servers"]:
                    self.assertEqual(after["mcp_servers"]["custom"], before["mcp_servers"]["custom"])
                else:
                    self.assertEqual(after["mcp_servers"]["custom"]["command"], "different")

    def test_mixed_manifest_and_invalid_input(self):
        target = self.directory / "mixed.toml"
        original = '# keep\n[mcp_servers."custom"]\ncommand = "mine"\n'
        target.write_text(original)
        manifest = {"custom": {"command": "ignored"}, "remote-server": {"url": "https://example.org/mcp"}, "local": {"command": "test", "args": ["one", "two"]}}
        result = self.invoke("codex", target, json.dumps(manifest))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(target.read_text().startswith(original))
        servers = tomllib.loads(target.read_text())["mcp_servers"]
        self.assertEqual(servers["custom"]["command"], "mine")
        self.assertEqual(servers["remote-server"]["url"], "https://example.org/mcp")
        self.assertEqual(servers["local"]["args"], ["one", "two"])
        before = target.read_bytes()
        result = self.invoke("codex", target, '{"bad": {"url": {}}}')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(target.read_bytes(), before)

    def test_claude_preserves_auth_state_and_other_servers(self):
        target = self.directory / ".claude.json"
        original = {"oauthAccount": {"uuid": "example"}, "mcpServers": {
            "other": {"command": "existing-server", "env": {"CUSTOM": "value"}},
        }}
        target.write_text(json.dumps(original))
        result = self.run_config("claude", target)
        self.assertEqual(result.returncode, 0, result.stderr)
        merged = json.loads(target.read_text())
        self.assertEqual(merged["oauthAccount"], original["oauthAccount"])
        self.assertEqual(merged["mcpServers"]["other"], original["mcpServers"]["other"])
        self.assertEqual(merged["mcpServers"]["serena"], {
            "type": "stdio", "command": self.command, "args": ["--context", "claude-code"],
        })
        first = target.read_bytes()
        self.assertEqual(self.run_config("claude", target).returncode, 0)
        self.assertEqual(target.read_bytes(), first)

    def test_codex_preserves_comments_and_nested_tables(self):
        target = self.directory / "config.toml"
        original = '# Keep this comment\nmodel = "custom"\n[mcp_servers.other]\ncommand = "existing"\n[profiles.mine]\nmodel = "chosen"\n'
        target.write_text(original)
        result = self.run_config("codex", target)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(target.read_text().startswith(original))
        merged = tomllib.loads(target.read_text())
        self.assertEqual(merged["profiles"]["mine"]["model"], "chosen")
        self.assertEqual(merged["mcp_servers"]["other"]["command"], "existing")
        self.assertEqual(merged["mcp_servers"]["serena"]["command"], self.command)
        self.assertEqual(merged["mcp_servers"]["serena"]["args"], ["--context", "codex"])
        first = target.read_bytes()
        self.assertEqual(self.run_config("codex", target).returncode, 0)
        self.assertEqual(target.read_bytes(), first)

    def test_explicit_serena_choices_are_preserved_byte_for_byte(self):
        for mode, original in (
            ("codex", '# custom\n[mcp_servers.serena]\ncommand = "my-serena"\nenabled = false\n'),
            ("claude", '{"mcpServers":{"serena":{"command":"my-serena"}},"other":true}'),
        ):
            with self.subTest(mode=mode):
                target = self.directory / mode
                target.write_text(original)
                result = self.run_config(mode, target)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(target.read_text(), original)

    def test_malformed_settings_are_not_replaced(self):
        for mode, original in (("codex", "not = [valid"), ("claude", '{"mcpServers": []}')):
            with self.subTest(mode=mode):
                target = self.directory / mode
                target.write_text(original)
                self.assertNotEqual(self.run_config(mode, target).returncode, 0)
                self.assertEqual(target.read_text(), original)

    def test_symlink_is_not_replaced_or_followed(self):
        original = self.directory / "original"
        original.write_text("{}")
        target = self.directory / "link"
        target.symlink_to(original)
        self.assertNotEqual(self.run_config("claude", target).returncode, 0)
        self.assertTrue(target.is_symlink())
        self.assertEqual(original.read_text(), "{}")

    def test_new_configuration_is_private(self):
        target = self.directory / "new/config.toml"
        result = self.run_config("codex", target)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(target.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
