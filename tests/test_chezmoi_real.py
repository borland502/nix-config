"""Offline integration coverage for external Git failure recovery."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ChezmoiRealTest(unittest.TestCase):
    def test_clone_and_pull_recovery_and_unique_logs(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            source, dest = base / "source", base / "dest"
            source.mkdir()
            dest.mkdir()
            env = dict(
                os.environ,
                HOME=tmp,
                XDG_CONFIG_HOME=str(base / "config"),
                XDG_CACHE_HOME=str(base / "cache"),
                XDG_DATA_HOME=str(base / "data"),
                XDG_STATE_HOME=str(base / "state"),
                GIT_CONFIG_NOSYSTEM="1",
            )
            external = source / ".chezmoiexternal.toml"
            repo = base / "remote.git"
            external.write_text(
                f'[".local/src/probe"]\ntype = "git-repo"\nurl = "{repo}"\nrefreshPeriod = "0s"\n'
            )
            (source / "dot_marker").write_text("applied\n")
            command = [
                "zsh",
                "-f",
                str(ROOT / "scripts/chezmoi-apply-tolerant.sh"),
                str(source),
                "--",
                "chezmoi",
                "--config",
                str(base / "chezmoi.toml"),
                "--source",
                str(source),
                "--destination",
                str(dest),
            ]

            def run():
                return subprocess.run(command, env=env, capture_output=True, text=True)

            clone = run()
            self.assertEqual(clone.returncode, 0, clone.stdout + clone.stderr)
            self.assertIn("re-applying without externals", clone.stderr)
            self.assertEqual((dest / ".marker").read_text(), "applied\n")
            subprocess.run(
                ["git", "init", "--bare", str(repo)],
                check=True,
                capture_output=True,
                env=env,
            )
            subprocess.run(
                ["git", "clone", str(repo), str(dest / ".local/src/probe")],
                check=True,
                capture_output=True,
                env=env,
            )
            shutil.rmtree(repo)
            pull = run()
            self.assertEqual(pull.returncode, 0, pull.stdout + pull.stderr)
            self.assertIn("re-applying without externals", pull.stderr)
            logs = list((base / "cache/claude").iterdir())
            self.assertEqual(len(logs), 6)


if __name__ == "__main__":
    unittest.main()
