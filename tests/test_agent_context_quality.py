import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "chezmoi/dot_local/lib"))


class ContextQualityTests(unittest.TestCase):
    def test_context_without_git_or_commands(self):
        from agent_tools.context import collect

        with tempfile.TemporaryDirectory() as directory:
            result = collect(Path(directory), env={"PATH": "", "HOME": directory})
        self.assertIsNone(result["repository"])
        self.assertEqual(result["dirty_files"], [])
        self.assertEqual(result["direnv"]["approval"], "unavailable")

    def test_linked_worktree_and_dirty_names(self):
        from agent_tools.context import collect

        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory) / "repo"
            repo.mkdir()
            subprocess.run(["git", "init", "-q", str(repo)], check=True)
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(repo),
                    "-c",
                    "user.name=Test",
                    "-c",
                    "user.email=test@example.invalid",
                    "commit",
                    "--allow-empty",
                    "-qm",
                    "initial",
                ],
                check=True,
            )
            linked = Path(directory) / "linked"
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(repo),
                    "worktree",
                    "add",
                    "-qb",
                    "fixture",
                    str(linked),
                ],
                check=True,
                capture_output=True,
            )
            (linked / "AGENTS.md").write_text("instructions")
            (linked / "odd name.txt").write_text("dirty")
            result = collect(linked)
            self.assertEqual(result["repository"], str(repo.resolve()))
            self.assertEqual(result["worktree"], str(linked.resolve()))
            self.assertEqual(result["branch"], "fixture")
            self.assertIn("odd name.txt", result["dirty_files"])
            self.assertIn(
                str((linked / "AGENTS.md").resolve()), result["instruction_paths"]
            )

    def test_installed_context_from_unrelated_cwd(self):
        import os
        import shutil

        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            lib = home / ".local/lib"
            shutil.copytree(
                ROOT / "chezmoi/dot_local/lib/agent_tools", lib / "agent_tools"
            )
            command = home / ".local/bin/agent-context"
            command.parent.mkdir(parents=True)
            shutil.copyfile(
                ROOT / "chezmoi/dot_local/bin/executable_agent-context", command
            )
            result = subprocess.run(
                [sys.executable, str(command), directory, "--json"],
                cwd="/",
                env={**os.environ, "HOME": directory},
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIsNone(json.loads(result.stdout)["repository"])

    def test_context_bounds_dirty_files_and_reports_approval(self):
        from agent_tools.context import collect
        import os

        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            subprocess.run(["git", "init", "-q", directory], check=True)
            for number in range(120):
                (base / f"dirty-{number}").touch()
            tools = base / "tools"
            tools.mkdir()
            adapter = tools / "direnv"
            adapter.write_text(
                '#!/bin/sh\n[ "$1" = status ] || exit 99\nprintf \'%s\' \'{"state":{"foundRC":{"allowed":1}}}\'\n'
            )
            adapter.chmod(0o755)
            result = collect(
                base,
                env={
                    **os.environ,
                    "PATH": str(tools) + os.pathsep + os.environ["PATH"],
                },
            )
            self.assertEqual(len(result["dirty_files"]), 100)
            self.assertTrue(result["dirty_files_truncated"])
            self.assertEqual(result["direnv"]["approval"], "denied")

    def test_installed_cache_tools_import_shared_modules(self):
        import os
        import shutil

        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            lib = home / ".local/lib"
            shutil.copytree(
                ROOT / "chezmoi/dot_local/lib/agent_tools", lib / "agent_tools"
            )
            shutil.copyfile(
                ROOT / "chezmoi/dot_local/lib/cache_scan.py", lib / "cache_scan.py"
            )
            command = home / ".local/bin/cache-scan"
            command.parent.mkdir(parents=True)
            shutil.copyfile(
                ROOT / "chezmoi/dot_local/bin/executable_cache-scan", command
            )
            collector = home / ".local/bin/ai-tools/agent-cache-capture"
            collector.parent.mkdir()
            shutil.copyfile(ROOT / "ai-tools/scripts/agent-cache-capture", collector)
            env = {
                **os.environ,
                "HOME": directory,
                "XDG_CACHE_HOME": str(home / ".cache"),
                "AGENT_TOOLS_LIB": str(lib),
            }
            for argv in (
                ["bash", str(command), "--json"],
                [sys.executable, str(collector), "--help"],
            ):
                result = subprocess.run(
                    argv, cwd="/", env=env, capture_output=True, text=True
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn("Traceback", result.stderr)

    def test_python_discovery_and_correctness(self):
        spec = importlib.util.spec_from_file_location(
            "lint_python", ROOT / "scripts/lint-python.py"
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            subprocess.run(["git", "init", "-q", directory], check=True)
            for name, body in {
                "ai-tools/scripts/worker": "#!/usr/bin/env -S python3 -u\nmissing()\n",
                "library.py": "x = 1\n",
                "shell": "#!/bin/sh\nexit 0\n",
                "vendor/ignored.py": "bad syntax!",
            }.items():
                target = base / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(body)
            self.assertEqual(
                module.discover(base), ["ai-tools/scripts/worker", "library.py"]
            )
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts/lint-python.py"),
                    "--root",
                    directory,
                ],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("F821", result.stdout)

    def test_budget_rejects_new_oversized_skill_and_broken_reference(self):
        spec = importlib.util.spec_from_file_location(
            "budget", ROOT / "scripts/check-agent-context-budget.py"
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            skill = base / "ai-tools/skills/new/SKILL.md"
            skill.parent.mkdir(parents=True)
            skill.write_text("x" * 6000 + "\n[missing](references/missing.md)\n")
            report = module.inventory(base)
            self.assertTrue(any("budget" in error for error in report["errors"]))
            self.assertTrue(any("reference" in error for error in report["errors"]))

    def test_grandfathering_is_exact_and_runtime_home_links_are_not_relative(self):
        import hashlib

        spec = importlib.util.spec_from_file_location(
            "budget", ROOT / "scripts/check-agent-context-budget.py"
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            skill = base / "ai-tools/skills/legacy/SKILL.md"
            skill.parent.mkdir(parents=True)
            skill.write_text("x" * 6000 + "\n[installed](~/.local/bin/example)\n")
            manifest = base / "scripts/agent-context-grandfather.json"
            manifest.parent.mkdir()
            manifest.write_text(
                json.dumps(
                    {
                        str(skill.relative_to(base)): {
                            "sha256": hashlib.sha256(skill.read_bytes()).hexdigest()
                        }
                    }
                )
            )
            report = module.inventory(base)
            self.assertFalse(
                any(
                    "budget" in error or "reference" in error
                    for error in report["errors"]
                )
            )
            skill.write_text(skill.read_text() + "changed")
            self.assertTrue(
                any("budget" in error for error in module.inventory(base)["errors"])
            )


if __name__ == "__main__":
    unittest.main()
