"""Behavioral tests for sudo's desktop askpass dispatcher."""

from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DISPATCHER = ROOT / "ai-tools/scripts/sudo-askpass"
MODULE = ROOT / "home-manager/modules/sudo-askpass.nix"


class DispatcherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.bin = Path(self.temp.name)
        # Mask all absolute helper lookups so tests never launch host GUI programs.
        bash_env = self.bin / "bash-env"
        bash_env.write_text(
            "command() {\n"
            '  if [ "$1" = "-v" ] && [[ "$2" = /* ]]; then return 1; fi\n'
            '  builtin command "$@"\n'
            "}\n"
        )
        self.env = {
            "PATH": str(self.bin),
            "DISPLAY": ":fixture",
            "BASH_ENV": str(bash_env),
        }

    def helper(self, name, body):
        helper = self.bin / name
        helper.write_text("#!/bin/sh\n" + body + "\n")
        helper.chmod(0o755)

    def run_dispatcher(self, *args):
        return subprocess.run(
            ["/bin/bash", str(DISPATCHER), *args],
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_fixture_masks_existing_absolute_executable(self):
        result = subprocess.run(
            ["/bin/bash", "-c", "command -v /bin/sh"],
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_forwards_prompt_and_clears_ssh_confirmation_mode(self):
        self.helper("ksshaskpass", 'printf "%s|%s" "$1" "${SSH_ASKPASS_PROMPT-unset}"')
        self.env["SSH_ASKPASS_PROMPT"] = "confirm"
        result = self.run_dispatcher("synthetic prompt")
        self.assertEqual(
            (result.returncode, result.stdout), (0, "synthetic prompt|unset")
        )

    def test_cancellation_does_not_try_another_helper(self):
        self.helper("ksshaskpass", "exit 23")
        self.helper("ssh-askpass", 'printf "synthetic fallback"')
        result = self.run_dispatcher("prompt")
        self.assertEqual((result.returncode, result.stdout), (23, ""))

    def test_missing_helper_fails_without_output(self):
        result = self.run_dispatcher("prompt")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("helper", result.stderr.lower())

    def test_missing_display_fails_before_launch(self):
        self.helper("ksshaskpass", 'printf "synthetic marker"')
        self.env.pop("DISPLAY")
        result = self.run_dispatcher("prompt")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("display", result.stderr.lower())

    def test_wayland_and_alternative_helper(self):
        self.env.pop("DISPLAY")
        self.env["WAYLAND_DISPLAY"] = "fixture"
        self.helper("lxqt-openssh-askpass", 'printf "%s" "$1"')
        result = self.run_dispatcher("wayland prompt")
        self.assertEqual((result.returncode, result.stdout), (0, "wayland prompt"))


class ModuleTests(unittest.TestCase):
    def evaluate(self, linux):
        expr = """let
          module = import (builtins.toPath %s) {
            config.home.homeDirectory = "/home/test user";
            pkgs = { stdenv.isLinux = %s; writeShellScript = name: source: "/fixture/script"; };
            lib.mkIf = condition: value: if condition then value else {};
          };
        in builtins.toJSON module""" % (
            repr(str(MODULE)).replace("'", '"'),
            str(linux).lower(),
        )
        result = subprocess.run(
            ["nix", "eval", "--impure", "--raw", "--expr", expr],
            text=True,
            capture_output=True,
            check=True,
        )
        import json

        return json.loads(result.stdout)

    def test_linux_exports_default_and_preserves_override_in_both_fragments(self):
        config = self.evaluate(True)
        for fragment in (
            config["home"]["sessionVariablesExtra"],
            config["programs"]["zsh"]["envExtra"],
        ):
            for value, expected in (
                (None, "/home/test user/.local/bin/ai-tools/sudo-askpass"),
                ("/explicit helper", "/explicit helper"),
            ):
                env = {} if value is None else {"SUDO_ASKPASS": value}
                result = subprocess.run(
                    ["/bin/sh", "-c", fragment + '\nprintf "%s" "$SUDO_ASKPASS"'],
                    env=env,
                    text=True,
                    capture_output=True,
                    check=True,
                )
                self.assertEqual(result.stdout, expected)

    def test_darwin_is_disabled(self):
        self.assertEqual(self.evaluate(False), {})


if __name__ == "__main__":
    unittest.main()
