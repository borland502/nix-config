import os
import pty
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class HostActions(unittest.TestCase):
    def run_in_terminal(self, args, *, cwd, env, stderr_terminal=True):
        master, slave = pty.openpty()
        try:
            result = subprocess.run(
                args,
                cwd=cwd,
                env=env,
                stdout=slave,
                stderr=slave if stderr_terminal else subprocess.PIPE,
                text=True,
            )
            # macOS discards unread PTY output when the last slave closes.
            os.set_blocking(master, False)
            output = bytearray()
            while True:
                try:
                    chunk = os.read(master, 4096)
                except BlockingIOError:
                    break
                if not chunk:
                    break
                output.extend(chunk)
            result.stdout = output.decode()
            result.stderr = result.stderr or ""
            return result
        finally:
            os.close(master)
            os.close(slave)

    def test_generation_finishes_before_chezmoi_apply(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            subprocess.run(["git", "init", "-q"], cwd=root, check=True)
            shutil.copy(ROOT / "taskfile.yaml", root / "taskfile.yaml")
            for item in ("taskfiles", "pkgs"):
                shutil.copytree(ROOT / item, root / item)
            (root / "scripts").mkdir()
            for script in ("chezmoi-apply-tolerant.sh", "host-action.sh"):
                source = ROOT / "scripts" / script
                if source.exists():
                    shutil.copy(source, root / "scripts" / script)
            quality = root / "taskfiles/quality.yml"
            quality.write_text(
                "version: '3'\ntasks:\n  fmt:\n    cmd: 'true'\n  generate:agent-instructions:\n    cmd: 'sleep 1; echo generated >> \"$TRACE\"'\n"
            )
            bins = root / "bin"
            bins.mkdir()
            for name in ("nix", "chezmoi", "brew"):
                stub = bins / name
                stub.write_text("#!/bin/sh\necho " + name + ' "$@" >> "$TRACE"\n')
                stub.chmod(0o755)
            (root / "scripts/chezmoi-apply-tolerant.sh").write_text(
                'echo applied >> "$TRACE"\n'
            )
            trace = root / "trace"
            env = dict(
                os.environ,
                HOME=str(root),
                PATH=str(bins) + os.pathsep + os.environ["PATH"],
                TRACE=str(trace),
                INSIDE_DEVCONTAINER="1",
            )
            result = subprocess.run(
                ["task", "switch"], cwd=root, env=env, capture_output=True, text=True
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            lines = trace.read_text().splitlines()
            self.assertLess(lines.index("generated"), lines.index("applied"), lines)

    def test_dispatch_commands_and_environment(self):
        cases = [
            ("build", "darwin", "mac", "darwin-rebuild build --flake .#mac | "),
            (
                "dry-build",
                "nixos",
                "wsl",
                "nixos-rebuild dry-build --flake path:/src#wsl | experimental-features = nix-command flakes",
            ),
            (
                "build",
                "standalone",
                "linux",
                "nix run .#home-manager -- build --flake .#user@linux | ",
            ),
            (
                "build",
                "devcontainer",
                "linux",
                "nix build .#homeConfigurations.vscode@devcontainer.activationPackage | ",
            ),
            (
                "switch",
                "standalone",
                "wsl",
                "nix run path:/src#home-manager -- switch --flake path:/src#user@wsl -b backup | experimental-features = nix-command flakes",
            ),
            (
                "switch",
                "devcontainer",
                "linux",
                "nix run .#home-manager -- switch --flake .#vscode@devcontainer -b bak-devcontainer | ",
            ),
            ("switch", "nixos", "wsl", "nixos-wrapper path:/src#wsl | "),
            ("switch-update-brew", "darwin", "mac", "brew update --quiet | "),
        ]
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            bins = root / "bin"
            bins.mkdir()
            scripts = root / "scripts"
            scripts.mkdir()
            for name in ("nix", "nixos-rebuild", "darwin-rebuild", "brew"):
                stub = bins / name
                stub.write_text(
                    '#!/bin/sh\nprintf "%s %s | %s\\n" "'
                    + name
                    + '" "$*" "${NIX_CONFIG:-}" >> "$TRACE"\n'
                )
                stub.chmod(0o755)
            for name in ("nixos", "darwin"):
                (scripts / (name + "-switch-tolerant.sh")).write_text(
                    'printf "%s-wrapper %s | %s\\n" '
                    + name
                    + ' "$*" "${NIX_CONFIG:-}" >> "$TRACE"\n'
                )
            trace = root / "trace"
            env = dict(
                os.environ,
                HOME=str(root),
                PATH=str(bins) + os.pathsep + os.environ["PATH"],
                TRACE=str(trace),
            )
            env.pop("NIX_CONFIG", None)
            for action, platform, host, expected in cases:
                with self.subTest(action=action, platform=platform, host=host):
                    trace.unlink(missing_ok=True)
                    sysflake = "path:/src#wsl" if host == "wsl" else ".#" + host
                    homeflake = (
                        "path:/src#user@wsl" if host == "wsl" else ".#user@linux"
                    )
                    app = (
                        "path:/src#home-manager" if host == "wsl" else ".#home-manager"
                    )
                    result = subprocess.run(
                        [
                            "zsh",
                            "-f",
                            str(ROOT / "scripts/host-action.sh"),
                            action,
                            platform,
                            host,
                            sysflake,
                            homeflake,
                            app,
                            "vscode@devcontainer",
                        ],
                        cwd=root,
                        env=env,
                        capture_output=True,
                        text=True,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn(expected, trace.read_text().splitlines())

    def test_build_monitor_preserves_output_environment_and_failures(self):
        cases = [
            ("darwin", "mac", "darwin-rebuild"),
            ("nixos", "wsl", "nixos-rebuild"),
            ("standalone", "wsl", "nix"),
            ("devcontainer", "linux", "nix"),
        ]
        zsh = shutil.which("zsh")
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            trace = root / "trace"
            for name in ("nix", "nixos-rebuild", "darwin-rebuild"):
                stub = root / name
                stub.write_text(
                    '#!/bin/sh\nprintf "%s | %s\\n" "'
                    + name
                    + '" "${NIX_CONFIG:-}" >> "$TRACE"\n'
                    'printf "build output\\n"\nprintf "build diagnostic\\n" >&2\n'
                    'exit "$BUILD_EXIT"\n'
                )
                stub.chmod(0o755)
            monitor = root / "nom"
            for monitored in (False, True):
                if monitored:
                    monitor.write_text(
                        '#!/bin/sh\nprintf "monitor\\n" >> "$TRACE"\n'
                        '/bin/cat\nexit "$MONITOR_EXIT"\n'
                    )
                    monitor.chmod(0o755)
                for platform, host, command in cases:
                    exits = ((0, 0), (7, 0), (0, 9)) if monitored else ((0, 0), (7, 0))
                    for build_exit, monitor_exit in exits:
                        with self.subTest(
                            platform=platform,
                            monitored=monitored,
                            build_exit=build_exit,
                            monitor_exit=monitor_exit,
                        ):
                            trace.unlink(missing_ok=True)
                            env = dict(
                                os.environ,
                                PATH=str(root),
                                HOME=str(root),
                                TRACE=str(trace),
                                BUILD_EXIT=str(build_exit),
                                MONITOR_EXIT=str(monitor_exit),
                            )
                            env.pop("NIX_CONFIG", None)
                            result = self.run_in_terminal(
                                [
                                    zsh,
                                    "-f",
                                    str(ROOT / "scripts/host-action.sh"),
                                    "build",
                                    platform,
                                    host,
                                    "path:/src#wsl",
                                    ".#user",
                                    ".#home-manager",
                                    "vscode@devcontainer",
                                ],
                                cwd=root,
                                env=env,
                            )
                            self.assertEqual(
                                result.returncode,
                                monitor_exit or build_exit,
                                result.stdout + result.stderr,
                            )
                            self.assertIn("build output", result.stdout)
                            self.assertIn(
                                "build diagnostic", result.stdout + result.stderr
                            )
                            lines = trace.read_text().splitlines()
                            expected_config = (
                                "experimental-features = nix-command flakes"
                                if host == "wsl"
                                else ""
                            )
                            self.assertIn(command + " | " + expected_config, lines)
                            self.assertEqual(lines.count("monitor"), int(monitored))

    def test_captured_build_output_bypasses_monitor(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            for name, content in (
                ("darwin-rebuild", '#!/bin/sh\nprintf "build output\\n"\nexit 7\n'),
                ("nom", '#!/bin/sh\nprintf "unexpected monitor\\n"\nexit 99\n'),
            ):
                stub = root / name
                stub.write_text(content)
                stub.chmod(0o755)
            result = subprocess.run(
                [
                    shutil.which("zsh"),
                    "-f",
                    str(ROOT / "scripts/host-action.sh"),
                    "build",
                    "darwin",
                    "mac",
                    ".#mac",
                    ".#user",
                    ".#home-manager",
                    "vscode@devcontainer",
                ],
                cwd=root,
                env=dict(os.environ, PATH=str(root), HOME=str(root)),
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 7, result.stdout + result.stderr)
            self.assertEqual(result.stdout, "build output\n")

    def test_redirected_build_stderr_bypasses_monitor(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            for name, content in (
                (
                    "darwin-rebuild",
                    '#!/bin/sh\nprintf "build output\\n"\n'
                    'printf "build diagnostic\\n" >&2\nexit 7\n',
                ),
                ("nom", '#!/bin/sh\nprintf "unexpected monitor\\n"\nexit 99\n'),
            ):
                stub = root / name
                stub.write_text(content)
                stub.chmod(0o755)
            result = self.run_in_terminal(
                [
                    shutil.which("zsh"),
                    "-f",
                    str(ROOT / "scripts/host-action.sh"),
                    "build",
                    "darwin",
                    "mac",
                    ".#mac",
                    ".#user",
                    ".#home-manager",
                    "vscode@devcontainer",
                ],
                cwd=root,
                env=dict(os.environ, PATH=str(root), HOME=str(root)),
                stderr_terminal=False,
            )
            self.assertEqual(result.returncode, 7, result.stdout + result.stderr)
            self.assertEqual(result.stdout.strip(), "build output")
            self.assertEqual(result.stderr, "build diagnostic\n")

    def test_dry_build_does_not_use_monitor(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            for name, content in (
                ("darwin-rebuild", '#!/bin/sh\nprintf "%s\\n" "$*"\n'),
                ("nom", "#!/bin/sh\nexit 99\n"),
            ):
                stub = root / name
                stub.write_text(content)
                stub.chmod(0o755)
            result = subprocess.run(
                [
                    shutil.which("zsh"),
                    "-f",
                    str(ROOT / "scripts/host-action.sh"),
                    "dry-build",
                    "darwin",
                    "mac",
                    ".#mac",
                    ".#user",
                    ".#home-manager",
                    "vscode@devcontainer",
                ],
                cwd=root,
                env=dict(os.environ, PATH=str(root), HOME=str(root)),
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "build --dry-run --flake .#mac")

    def test_invalid_platform_fails_before_update(self):
        with tempfile.TemporaryDirectory() as tmp:
            nix = pathlib.Path(tmp) / "nix"
            nix.write_text("#!/bin/sh\nexit 0\n")
            nix.chmod(0o755)
            result = subprocess.run(
                [
                    "zsh",
                    "-f",
                    str(ROOT / "scripts/host-action.sh"),
                    "upgrade",
                    "invalid",
                    "linux",
                    "x",
                    "x",
                    "x",
                    "x",
                ],
                env=dict(
                    os.environ, PATH=tmp + os.pathsep + os.environ["PATH"], HOME=tmp
                ),
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn("Unknown platform", result.stderr)

    def test_upgrade_updates_before_switch_and_runs_helpers(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            bins = root / "bin"
            bins.mkdir()
            helpers = root / ".local/bin"
            helpers.mkdir(parents=True)
            trace = root / "trace"
            for target in (
                bins / "nix",
                helpers / "ensure-nix-zsh-shell",
                helpers / "update-agent-clis",
            ):
                target.write_text(
                    '#!/bin/sh\necho "' + target.name + ' $*" >> "$TRACE"\n'
                )
                target.chmod(0o755)
            env = dict(
                os.environ,
                HOME=str(root),
                PATH=str(bins) + os.pathsep + os.environ["PATH"],
                TRACE=str(trace),
            )
            result = subprocess.run(
                [
                    "zsh",
                    "-f",
                    str(ROOT / "scripts/host-action.sh"),
                    "upgrade",
                    "standalone",
                    "linux",
                    ".#linux",
                    ".#user",
                    ".#home-manager",
                    "vscode@devcontainer",
                ],
                cwd=root,
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                trace.read_text().splitlines(),
                [
                    "nix flake update",
                    "nix run .#home-manager -- switch --flake .#user -b backup",
                    "ensure-nix-zsh-shell ",
                    "update-agent-clis ",
                ],
            )


if __name__ == "__main__":
    unittest.main()
