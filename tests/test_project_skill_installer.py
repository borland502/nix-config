"""Offline installer behavior against disposable projects and harness homes."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "ai-tools/scripts/install-project-skill"
TEMPLATES = ROOT / "ai-tools/project-skills"


class ProjectSkillInstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.home = self.base / "home"
        self.home.mkdir()
        self.project = self.base / "project"
        self.project.mkdir()
        (self.project / ".git").mkdir()
        self.env = dict(os.environ, HOME=str(self.home),
                        XDG_DATA_HOME=str(self.home / ".local/share"),
                        XDG_CONFIG_HOME=str(self.home / ".config"),
                        CODEX_HOME=str(self.home / ".config/codex"))

    def run_install(self, name="database-investigation", harness="codex", **kwargs):
        command = [sys.executable, str(kwargs.pop("script", INSTALLER)), name,
                   "--project", str(kwargs.pop("project", self.project)),
                   "--harness", harness]
        if "templates" in kwargs:
            command += ["--templates", str(kwargs.pop("templates"))]
        self.assertFalse(kwargs)
        return subprocess.run(command, env=self.env, cwd=self.base,
                              capture_output=True, text=True, timeout=5)

    def test_source_install_copies_each_template_and_harness(self):
        for harness in ("codex", "claude", "copilot"):
            for name in ("database-investigation", "api-contract-parity"):
                result = self.run_install(name, harness)
                self.assertEqual(result.returncode, 0, result.stderr)
                folder = {"copilot": ".github", "codex": ".agents", "claude": ".claude"}[harness]
                target = self.project / folder / "skills" / name
                self.assertEqual((target / "SKILL.md").read_bytes(),
                                 (TEMPLATES / name / "SKILL.md").read_bytes())
                self.assertTrue((target / "references/project-baseline.md").is_file())

    def test_existing_skill_is_unchanged(self):
        self.assertEqual(self.run_install().returncode, 0)
        target = self.project / ".agents/skills/database-investigation/SKILL.md"
        target.write_text("project customization")
        result = self.run_install()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(target.read_text(), "project customization")

    def test_existing_empty_target_is_not_overwritten(self):
        target = self.project / ".agents/skills/database-investigation"
        target.mkdir(parents=True)
        self.assertNotEqual(self.run_install().returncode, 0)
        self.assertEqual(list(target.iterdir()), [])

    def test_redirected_harness_parent_is_refused(self):
        global_state = self.home / ".config/codex"
        global_state.mkdir(parents=True)
        (self.project / ".agents").symlink_to(global_state, target_is_directory=True)
        self.assertNotEqual(self.run_install().returncode, 0)
        self.assertEqual(list(global_state.iterdir()), [])

    def test_redirected_skills_parent_is_refused(self):
        (self.project / ".agents").mkdir()
        (self.project / ".agents/skills").symlink_to(self.home, target_is_directory=True)
        self.assertNotEqual(self.run_install().returncode, 0)
        self.assertFalse((self.home / "database-investigation").exists())

    def test_dangling_destination_link_is_refused(self):
        target = self.project / ".agents/skills/database-investigation"
        target.parent.mkdir(parents=True)
        target.symlink_to(self.base / "missing")
        self.assertNotEqual(self.run_install().returncode, 0)
        self.assertTrue(target.is_symlink())

    def test_global_harness_repository_is_refused(self):
        project = self.home / ".config/codex"
        (project / ".git").mkdir(parents=True)
        self.assertNotEqual(self.run_install(project=project).returncode, 0)
        self.assertFalse((project / ".agents").exists())

    def test_explicit_project_is_required_to_be_repository(self):
        other = self.base / "other"
        other.mkdir()
        self.assertNotEqual(self.run_install(project=other).returncode, 0)
        self.assertEqual(list(other.iterdir()), [])

    def test_shared_global_agents_repository_is_refused(self):
        project = self.home / ".agents"
        (project / ".git").mkdir(parents=True)
        result = self.run_install(project=project)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((project / ".agents").exists())

    def check_configured_global_roots(self, descendant=False, env_link=False,
                                      project_link=False):
        for variable, harness in (("CLAUDE_CONFIG_DIR", "claude"),
                                  ("COPILOT_HOME", "copilot")):
            with self.subTest(variable=variable, descendant=descendant,
                              env_link=env_link, project_link=project_link):
                global_root = self.base / variable
                global_root.mkdir()
                alias = self.base / (variable + "-alias")
                alias.symlink_to(global_root, target_is_directory=True)
                self.env[variable] = str(alias if env_link else global_root)
                target = global_root / "nested" if descendant else global_root
                (target / ".git").mkdir(parents=True)
                requested = alias / "nested" if project_link else target
                result = self.run_install(project=requested, harness=harness)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("global harness state", result.stderr)
                self.assertEqual(sorted(p.name for p in target.iterdir()), [".git"])

    def test_configured_global_roots_are_refused(self):
        self.check_configured_global_roots()

    def test_configured_global_descendants_are_refused(self):
        self.check_configured_global_roots(descendant=True)

    def test_configured_global_root_symlinks_are_canonicalized(self):
        self.check_configured_global_roots(descendant=True, env_link=True)

    def test_project_alias_into_configured_global_root_is_refused(self):
        self.check_configured_global_roots(descendant=True, project_link=True)

    def test_project_ancestor_of_configured_destination_is_refused(self):
        for variable, harness, folder in (("CLAUDE_CONFIG_DIR", "claude", ".claude"),
                                           ("COPILOT_HOME", "copilot", ".github")):
            for suffix in (folder, folder + "/skills/database-investigation"):
                with self.subTest(variable=variable, protected=suffix):
                    project = self.base / (variable + "-" + suffix.replace("/", "-"))
                    (project / ".git").mkdir(parents=True)
                    self.env[variable] = str(project / suffix)
                    result = self.run_install(harness=harness, project=project)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("global harness state", result.stderr)
                    self.assertEqual(sorted(p.name for p in project.iterdir()), [".git"])

    def test_home_repository_is_refused(self):
        (self.home / ".git").mkdir()
        self.assertNotEqual(self.run_install(project=self.home).returncode, 0)

    def test_template_traversal_is_refused(self):
        self.assertNotEqual(self.run_install("../../escape").returncode, 0)
        self.assertFalse((self.project / ".agents").exists())

    def test_source_symlinks_are_refused_before_destination_creation(self):
        source = self.base / "templates"
        template = source / "database-investigation"
        template.mkdir(parents=True)
        (template / "SKILL.md").write_text("valid")
        (template / "reference.md").symlink_to(self.base / "missing")
        self.assertNotEqual(self.run_install(templates=source).returncode, 0)
        self.assertFalse((self.project / ".agents").exists())

    def test_installed_script_uses_data_home_from_unrelated_cwd(self):
        script = self.home / ".local/bin/ai-tools/install-project-skill"
        script.parent.mkdir(parents=True)
        shutil.copyfile(INSTALLER, script)
        share = self.home / ".local/share/agent-tools/project-skills"
        shutil.copytree(TEMPLATES, share)
        result = self.run_install(script=script)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.project / ".agents/skills/database-investigation/SKILL.md").is_file())


if __name__ == "__main__":
    unittest.main()
