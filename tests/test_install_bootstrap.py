#!/usr/bin/env python3
"""install.sh is the one bootstrap that runs before zsh exists, so it must stay bash-3.2-compatible."""

import re
import subprocess
import os
import tempfile
import unittest
from pathlib import Path

INSTALL = Path(__file__).resolve().parents[1] / "install.sh"
# Constructs bash 3.2 lacks or treats differently, with the reason.
BASH4_ONLY = {
    r"\bmapfile\b|\breadarray\b": "bash 4 builtin",
    r"\bdeclare\s+-[a-zA-Z]*A|\blocal\s+-[a-zA-Z]*[An]|\btypeset\s+-[a-zA-Z]*A": "associative array or nameref",
    r"\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^|,|\^)\}": "case-modification expansion",
    r";;&|;&": "case fall-through",
    r"\|&": "pipe-stderr shorthand",
    r"\bcoproc\b": "coproc",
    r"\$\{[A-Za-z_][A-Za-z0-9_]*\[@\]:": "array slicing (empty-safe only on 4.4+)",
}


class InstallBootstrapContract(unittest.TestCase):
    def test_header_declares_the_contract(self):
        header = "\n".join(INSTALL.read_text().splitlines()[:12])
        self.assertIn("bash 3.2", header)

    def test_no_bash4_only_constructs(self):
        code = "\n".join(
            line
            for line in INSTALL.read_text().splitlines()
            if not line.lstrip().startswith("#")
        )
        found = [
            f"{why}: {m.group(0)}"
            for pattern, why in BASH4_ONLY.items()
            for m in re.finditer(pattern, code)
        ]
        self.assertEqual(found, [])

    def test_every_array_expansion_has_a_nonempty_literal(self):
        code = INSTALL.read_text()
        for name in set(re.findall(r'"\$\{([A-Za-z_][A-Za-z0-9_]*)\[@\]\}"', code)):
            self.assertRegex(
                code,
                rf"(?m)^\s*{name}=\(\s*[^)\s]",
                f"{name} may be empty under set -u on bash 3.2",
            )

    @unittest.skipUnless(Path("/bin/bash").exists(), "needs /bin/bash")
    def test_parses_under_system_bash(self):
        result = subprocess.run(
            ["/bin/bash", "-n", str(INSTALL)], capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_every_nix_shell_provides_zsh(self):
        # The tasks install.sh runs call zsh scripts (task switch, chezmoi apply),
        # and a fresh Linux or NixOS-WSL host has no zsh until the first switch.
        shells = re.findall(r"nix shell ([^\n]*?)--command", INSTALL.read_text())
        self.assertTrue(shells, "expected nix shell invocations in install.sh")
        for packages in shells:
            self.assertIn("nixpkgs#zsh", packages, f"nix shell without zsh: {packages}")

    def test_repo_scripts_run_through_run_zsh(self):
        # Repo scripts are zsh. install.sh may run one only through _run_zsh, which
        # falls back to `nix shell nixpkgs#zsh` before the first switch provides zsh.
        code = INSTALL.read_text()
        self.assertEqual(re.findall(r'\bbash "\$_[a-z_]+"', code), [])
        self.assertRegex(code, r"(?m)^_run_zsh\(\) \{")
        for script in ("_bootstrap_win", "_provision_secrets"):
            self.assertIn(f'_run_zsh "${script}"', code)


class ToolsOnlyBehavior(unittest.TestCase):
    def run_bootstrap(self, missing=(), failure=None):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            log = root / "calls"
            for name in ("dirname", "mkdir", "mktemp", "rm", "sh"):
                (bin_dir / name).symlink_to(
                    "/bin/" + name
                    if Path("/bin/" + name).exists()
                    else "/usr/bin/" + name
                )
            for name in ("git", "curl", "task", "apt-get", "sudo", "nix"):
                if name in missing:
                    continue
                body = '#!/bin/bash\necho "' + name + ' $*" >> "$CALL_LOG"\n'
                if name == failure:
                    body += "exit 42\n"
                elif name == "sudo":
                    body += '"$@"\n'
                elif name == "curl" and failure == "installer":
                    body += 'printf "#!/bin/sh\\nexit 42\\n" > "$3"\n'
                elif name == "curl":
                    body += (
                        'printf "#!/bin/sh\necho installer >> "$CALL_LOG"\n" > "$3"\n'
                    )
                (bin_dir / name).write_text(body)
                (bin_dir / name).chmod(0o755)
            env = dict(
                os.environ,
                HOME=str(root),
                TMPDIR=str(root),
                PATH=str(bin_dir),
                CALL_LOG=str(log),
            )
            result = subprocess.run(
                ["/bin/bash", str(INSTALL), "--tools-only"],
                env=env,
                capture_output=True,
                text=True,
            )
            return (
                result,
                log.read_text() if log.exists() else "",
                list(root.glob("task-installer.*")),
            )

    def test_existing_tools_exit_before_nix(self):
        result, calls, _ = self.run_bootstrap()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, "")

    def test_missing_task_downloads_and_cleans_up(self):
        result, calls, leftovers = self.run_bootstrap(missing=("task",))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("curl ", calls)
        self.assertIn("installer", calls)
        self.assertEqual(leftovers, [])
        self.assertNotIn("nix ", calls)

    def test_missing_git_installs_with_apt(self):
        result, calls, _ = self.run_bootstrap(missing=("git",))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("apt-get install -y git", calls)
        self.assertNotIn("nix ", calls)

    def test_missing_curl_installs_with_apt(self):
        result, calls, _ = self.run_bootstrap(missing=("curl",))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("apt-get install -y curl", calls)

    def test_download_and_package_failures_propagate(self):
        for missing, failure in [
            (("task",), "curl"),
            (("git",), "apt-get"),
            (("task",), "installer"),
        ]:
            with self.subTest(failure=failure):
                result, calls, leftovers = self.run_bootstrap(
                    missing=missing, failure=failure
                )
                self.assertEqual(result.returncode, 42)
                self.assertEqual(leftovers, [])
                self.assertNotIn("nix ", calls)

    def test_envrc_load_has_no_installer_side_effects(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            log = root / "calls"
            for name in ("mkdir", "sudo", "curl", "apt-get", "task", "nix"):
                stub = bin_dir / name
                stub.write_text('#!/bin/bash\necho called >> "$CALL_LOG"\n')
                stub.chmod(0o755)
            env = dict(os.environ, HOME=str(root), PATH=str(bin_dir), CALL_LOG=str(log))
            source = 'PATH_add() { :; }; use() { :; }; log_status() { :; }; source "$1"'
            result = subprocess.run(
                ["/bin/bash", "-c", source, "bash", str(INSTALL.parent / ".envrc")],
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(log.exists())
            self.assertFalse((root / ".local").exists())

    def test_envrc_has_no_install_side_effects(self):
        envrc = (INSTALL.parent / ".envrc").read_text()
        self.assertNotRegex(envrc, r"(?m)^\s*(?:sudo|mkdir|curl|sh -c)\b")
        self.assertIn("--tools-only", envrc)


if __name__ == "__main__":
    unittest.main()
