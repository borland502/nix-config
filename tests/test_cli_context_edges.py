"""Offline regressions for CLI help and unusual Git checkout layouts."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "chezmoi/dot_local/lib"
sys.path.insert(0, str(LIB))


class CliContextEdges(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name).resolve()
        tools = self.base / "bin"
        tools.mkdir()
        (tools / "git").symlink_to(shutil.which("git"))
        self.env = {
            "HOME": str(self.base),
            "PATH": str(tools),
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
            "AGENT_TOOLS_LIB": str(LIB),
            "PYTHONIOENCODING": "utf-8:strict",
        }

    def git(self, *args):
        return subprocess.run(
            ["git", *map(str, args)], env=self.env, check=True,
            capture_output=True, text=True,
        )

    def initialize(self, repo):
        self.git("init", "-q", repo)
        self.git("-C", repo, "-c", "user.name=Fixture", "-c",
                 "user.email=fixture@example.invalid", "commit", "--allow-empty",
                 "-qm", "initial")

    def context(self, repo):
        from agent_tools.context import collect

        return collect(repo, env=self.env)

    def test_help_before_configuration_with_closed_stdin(self):
        for flag in ("--help", "-h"):
            with self.subTest(flag=flag):
                before = sorted(str(p.relative_to(self.base)) for p in self.base.rglob("*"))
                result = subprocess.run(
                    [sys.executable, str(ROOT / "ai-tools/scripts/ops-agent.py"), flag],
                    cwd="/", env=self.env, stdin=subprocess.DEVNULL,
                    capture_output=True, text=True, timeout=5,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, "")
                for text in ("Usage:", "--tool", "--input-file", "--test", "prompt", "jira_get_issue"):
                    self.assertIn(text, result.stdout)
                self.assertNotIn("provision", result.stdout)
                self.assertEqual(before, sorted(str(p.relative_to(self.base)) for p in self.base.rglob("*")))

    def test_invalid_filename_bytes_render_in_json_and_strict_utf8(self):
        repo = self.base / "repo"
        self.initialize(repo)
        # macOS rejects invalid UTF-8 filenames at creation time. Inject only
        # that Git status record; all other Git queries and records stay real.
        adapter = self.base / "bin/git"
        real_git = str(adapter.resolve())
        adapter.unlink()
        adapter.write_text(
            f"#!{sys.executable}\n"
            "import os, subprocess, sys\n"
            f"real_git = {real_git!r}\n"
            "if sys.argv[1:2] == ['status']:\n"
            "    result = subprocess.run([real_git, *sys.argv[1:]], capture_output=True)\n"
            "    sys.stdout.buffer.write(b'?? invalid-\\xff.txt\\0' + result.stdout)\n"
            "    sys.stderr.buffer.write(result.stderr)\n"
            "    sys.exit(result.returncode)\n"
            "os.execv(real_git, [real_git, *sys.argv[1:]])\n"
        )
        adapter.chmod(0o755)
        (repo / "normal name.txt").touch()
        for number in range(110):
            (repo / f"z-{number:03}").touch()
        for flags in (("--json",), ()):
            with self.subTest(flags=flags):
                result = subprocess.run(
                    [sys.executable, str(ROOT / "chezmoi/dot_local/bin/executable_agent-context"), str(repo), *flags],
                    cwd="/", env=self.env, capture_output=True, text=True, timeout=5,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, "")
                if flags:
                    payload = json.loads(result.stdout)
                    self.assertIn("normal name.txt", payload["dirty_files"])
                    self.assertTrue(any(name.startswith("invalid-") for name in payload["dirty_files"]))
                    self.assertEqual(len(payload["dirty_files"]), 100)
                    self.assertTrue(payload["dirty_files_truncated"])
                else:
                    self.assertIn("invalid-", result.stdout)

    def test_separate_git_dir_uses_checkout_as_repository(self):
        repo = self.base / "checkout"
        metadata = self.base / "arbitrary-metadata" / "storage"
        metadata.parent.mkdir()
        self.git("init", "-q", "--separate-git-dir", metadata, repo)
        result = self.context(repo)
        self.assertEqual(result["repository"], str(repo))
        self.assertEqual(result["worktree"], str(repo))

    def test_submodule_uses_its_checkout_as_repository(self):
        source = self.base / "source"
        parent = self.base / "parent"
        self.initialize(source)
        self.initialize(parent)
        self.git("-C", parent, "-c", "protocol.file.allow=always", "submodule", "add", "-q", source, "module")
        submodule = parent / "module"
        result = self.context(submodule)
        self.assertEqual(result["repository"], str(submodule))
        self.assertEqual(result["worktree"], str(submodule))

    def test_separate_metadata_inside_unrelated_checkout_is_not_its_identity(self):
        repo = self.base / "checkout"
        metadata = self.base / "unrelated"
        self.initialize(metadata)
        self.git("init", "-q", "--separate-git-dir", metadata, repo)
        result = self.context(repo)
        self.assertEqual(result["repository"], str(repo))
        self.assertEqual(result["worktree"], str(repo))

    def test_normal_and_linked_checkout_identity_is_preserved(self):
        repo = self.base / "repo"
        linked = self.base / "linked"
        self.initialize(repo)
        self.git("-C", repo, "worktree", "add", "-qb", "fixture", linked)
        for checkout in (repo, linked):
            with self.subTest(checkout=checkout):
                result = self.context(checkout)
                self.assertEqual(result["repository"], str(repo))
                self.assertEqual(result["worktree"], str(checkout))


if __name__ == "__main__":
    unittest.main()
