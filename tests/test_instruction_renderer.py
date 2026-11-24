"""Instruction rendering is shared by Nix and committed non-Nix deployment."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RENDERER = ROOT / "scripts/render-agent-instructions.py"


class InstructionRendererTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.source = self.directory / "source.md"
        self.source.write_text(
            "# @@AGENT@@\n\nUse @@AGENT@@ twice.\n", encoding="utf-8"
        )
        self.manifest = self.directory / "targets.json"
        self.manifest.write_text(
            json.dumps(
                {
                    "frontmatter": {"description": "For {agent}", "applyTo": "**"},
                    "targets": {
                        "plain": {
                            "agent": "claude",
                            "frontmatter": False,
                            "filename": "CLAUDE.md",
                            "destinations": ["a/CLAUDE.md"],
                        },
                        "metadata": {
                            "agent": "copilot",
                            "frontmatter": True,
                            "filename": "instructions.md",
                            "destinations": [
                                "b with spaces/instructions.md",
                                "mirror.md",
                            ],
                        },
                    },
                }
            ),
            encoding="utf-8",
        )
        self.output = self.directory / "output with spaces"

    def invoke(self, *arguments):
        return subprocess.run(
            [
                sys.executable,
                str(RENDERER),
                "--source",
                str(self.source),
                "--manifest",
                str(self.manifest),
                *map(str, arguments),
            ],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_render_and_write_produce_identical_bytes_for_every_destination(self):
        result = self.invoke("write", self.output)
        self.assertEqual(result.returncode, 0, result.stderr)
        plain = "# claude\n\nUse claude twice.\n"
        metadata = '---\ndescription: "For copilot"\napplyTo: "**"\n---\n\n# copilot\n\nUse copilot twice.\n'
        self.assertEqual(self.invoke("render", "plain").stdout, plain)
        self.assertEqual(self.invoke("render", "metadata").stdout, metadata)
        self.assertEqual((self.output / "a/CLAUDE.md").read_bytes(), plain.encode())
        for destination in ("b with spaces/instructions.md", "mirror.md"):
            self.assertEqual(
                (self.output / destination).read_bytes(), metadata.encode()
            )

    def test_check_reports_stale_and_missing_without_modifying_outputs(self):
        self.assertEqual(self.invoke("write", self.output).returncode, 0)
        self.assertEqual(self.invoke("check", self.output).returncode, 0)
        stale = self.output / "a/CLAUDE.md"
        stale.write_text("manual edit\n", encoding="utf-8")
        (self.output / "mirror.md").unlink()
        result = self.invoke("check", self.output)
        self.assertEqual(result.returncode, 1)
        self.assertIn("a/CLAUDE.md", result.stderr)
        self.assertIn("mirror.md", result.stderr)
        self.assertEqual(stale.read_text(), "manual edit\n")
        self.assertFalse((self.output / "mirror.md").exists())


if __name__ == "__main__":
    unittest.main()
