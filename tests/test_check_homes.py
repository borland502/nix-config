"""Exercise the home evaluation task without running Nix builds or activation."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CheckHomesTest(unittest.TestCase):
    def run_task(self, system, failure=""):
        with tempfile.TemporaryDirectory() as tmp:
            bindir = Path(tmp) / "bin"
            bindir.mkdir()
            log = Path(tmp) / "calls"
            for name, script in {
                "uname": 'printf "%s\\n" "$FAKE_SYSTEM"',
                "nix": 'printf "%s\\n" "$*" >> "$CALL_LOG"; case "$*" in *"$FAIL_PATTERN"*) [ -z "$FAIL_PATTERN" ] || exit 19;; esac; case "$*" in *attrNames*) printf \'["first@host","arm@host"]\\n\';; esac',
            }.items():
                exe = bindir / name
                exe.write_text("#!/bin/sh\n" + script + "\n")
                exe.chmod(0o755)
            env = dict(
                os.environ,
                PATH=str(bindir) + os.pathsep + os.environ["PATH"],
                CALL_LOG=str(log),
                FAKE_SYSTEM=system,
                FAIL_PATTERN=failure,
            )
            result = subprocess.run(
                ["task", "--taskfile", "taskfiles/quality.yml", "check:homes"],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
            )
            return result, log.read_text().splitlines()

    def test_linux_evaluates_all_homes_without_build_or_activation(self):
        result, calls = self.run_task("Linux")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 3)
        self.assertIn("builtins.attrNames", calls[0])
        self.assertIn(".#homeConfigurations", calls[0])
        self.assertTrue(all("path:" not in call for call in calls))
        for name, call in zip(("first@host", "arm@host"), calls[1:]):
            self.assertIn(name, call)
            self.assertIn("activationPackage.drvPath", call)
            self.assertTrue(call.startswith("eval --raw "))

    def test_darwin_also_evaluates_system(self):
        result, calls = self.run_task("Darwin")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 4)
        self.assertIn("#darwinConfigurations.darwin.system.drvPath", calls[3])
        self.assertTrue(calls[3].startswith("eval --raw "))

    def test_failed_home_evaluation_stops_task(self):
        result, calls = self.run_task("Darwin", "first@host")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 2)

    def test_failed_darwin_evaluation_fails_task(self):
        result, calls = self.run_task("Darwin", "#darwinConfigurations")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 4)
