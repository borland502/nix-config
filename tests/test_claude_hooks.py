"""Claude Code hook scripts: cache stats, bash-habit hints, format-on-edit."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "ai-tools/scripts"


def transcript_line(read=10, creation=2, fresh=1):
    usage = {
        "cache_read_input_tokens": read,
        "cache_creation_input_tokens": creation,
        "input_tokens": fresh,
        "output_tokens": 3,
    }
    return json.dumps({"message": {"usage": usage}}) + "\n"


class CacheStats(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.home = Path(tmp.name)
        projects = self.home / ".config/claude/projects/p"
        projects.mkdir(parents=True)
        (projects / "other.jsonl").write_text(transcript_line(read=1000) * 5)
        self.log = self.home / ".cache/claude/cache-stats.log"

    def run_hook(self, payload):
        return subprocess.run(
            ["zsh", str(SCRIPTS / "claude-cache-stats")],
            input=json.dumps(payload),
            text=True,
            capture_output=True,
            env=dict(os.environ, HOME=str(self.home)),
            check=True,
        )

    def test_missing_transcript_logs_nothing(self):
        self.run_hook({"session_id": "s", "transcript_path": str(self.home / "missing.jsonl")})
        self.run_hook({"session_id": "s2"})
        self.assertFalse(self.log.exists() and self.log.read_text().strip())

    def test_hook_logs_only_its_own_transcript(self):
        own = self.home / "own.jsonl"
        own.write_text(transcript_line())
        self.run_hook({"session_id": "s", "transcript_path": str(own)})
        line = self.log.read_text().strip()
        self.assertIn("session=s msgs=1 ", line)
        self.assertIn("read=10 ", line)


class BashHabitsHint(unittest.TestCase):
    def hint(self, command, **env):
        result = subprocess.run(
            [sys.executable, "-I", str(SCRIPTS / "bash-habits-hint")],
            input=json.dumps({"tool_name": "Bash", "tool_input": {"command": command}}),
            text=True,
            capture_output=True,
            env=dict(os.environ, **env),
            check=True,
        )
        if not result.stdout.strip():
            return None
        out = json.loads(result.stdout)["hookSpecificOutput"]
        self.assertEqual(out["hookEventName"], "PreToolUse")
        self.assertNotIn("permissionDecision", out)
        return out["additionalContext"]

    def test_flags_each_legacy_habit(self):
        cases = {
            "cd /repo && git status": "cd DIR",
            "cd '/a b'; task lint": "cd DIR",
            "rg foo | grep bar": "`rg`",
            "direnv exec /repo grep -n x f": "`rg`",
            "find . -name '*.nix'": "`fd`",
            "sed -n 1,20p file.txt": "Read tool",
            "cat notes.md": "bat --plain",
            "cat > out.txt <<'EOF'\nhello\nEOF": "Write tool",
        }
        for command, needle in cases.items():
            with self.subTest(command=command):
                self.assertIn(needle, self.hint(command) or "")

    def test_clean_commands_stay_silent(self):
        for command in (
            "rg -n foo src",
            "git grep foo",
            "git log | sed -n 1,5p",
            "/bin/cat f | jq .",
            "cat f | jq .",
            "cd /repo",
            "rg x\ngrep y",
            'echo "unterminated && cd x',
        ):
            with self.subTest(command=command):
                self.assertIsNone(self.hint(command))

    def test_combined_hints_and_opt_out(self):
        text = self.hint("cd /r && grep x f")
        self.assertIn("cd DIR", text)
        self.assertIn("`rg`", text)
        self.assertIsNone(self.hint("cd /r && grep x f", BASH_HABITS_HINT="off"))

    def test_bad_payload_is_ignored(self):
        result = subprocess.run(
            [sys.executable, "-I", str(SCRIPTS / "bash-habits-hint")],
            input="not json", text=True, capture_output=True, check=False,
        )
        self.assertEqual((result.returncode, result.stdout), (0, ""))


class FormatOnEdit(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.repo = self.git_repo("nix-config")
        state = self.tmp / "state/chezmoi"
        state.mkdir(parents=True)
        (state / "nix-config-dir").write_text(f"{self.repo}\n")
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        self.calls = self.tmp / "calls"
        for tool in ("alejandra", "markdownlint-cli2"):
            fake = self.bin / tool
            fake.write_text(
                "#!/bin/sh\n"
                f'echo "{tool} $PWD $*" >> "{self.calls}"\n'
                f'if [ -n "$FAIL_{tool.split("-")[0].upper()}" ]; then echo "{tool}: boom" >&2; exit 1; fi\n'
            )
            fake.chmod(0o755)
        self.env = dict(
            os.environ,
            HOME=str(self.tmp),
            XDG_STATE_HOME=str(self.tmp / "state"),
            PATH=f"{self.bin}:{os.environ['PATH']}",
        )

    def git_repo(self, name):
        repo = self.tmp / name
        repo.mkdir()
        subprocess.run(["git", "init", "-q", str(repo)], check=True)
        subprocess.run(
            ["git", "-C", str(repo), "-c", "user.email=t@example.invalid", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "init"],
            check=True,
        )
        return repo

    def edit(self, path, **env):
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists():
            path.write_text("x\n")
        return subprocess.run(
            [sys.executable, "-I", str(SCRIPTS / "format-on-edit")],
            input=json.dumps({"tool_name": "Edit", "tool_input": {"file_path": str(path)}}),
            text=True,
            capture_output=True,
            env=dict(self.env, **env),
            check=False,
        )

    def called(self):
        return self.calls.read_text() if self.calls.exists() else ""

    def test_nix_in_repo_and_worktree_is_formatted(self):
        worktree = self.tmp / "wt"
        subprocess.run(["git", "-C", str(self.repo), "worktree", "add", "-q", str(worktree)], check=True)
        for recorded in (self.repo, worktree):
            with self.subTest(recorded=recorded):
                (self.tmp / "state/chezmoi/nix-config-dir").write_text(f"{recorded}\n")
                self.calls.unlink(missing_ok=True)
                self.assertEqual(self.edit(self.repo / "a.nix").returncode, 0)
                self.assertEqual(self.edit(worktree / "b.nix").returncode, 0)
                calls = self.called().splitlines()
                self.assertEqual(len(calls), 2)
                self.assertTrue(calls[0].endswith(f"--quiet {self.repo / 'a.nix'}"))
                self.assertTrue(calls[1].endswith("/wt/b.nix"))

    def test_nix_outside_repo_is_untouched(self):
        other = self.git_repo("other")
        self.assertEqual(self.edit(other / "a.nix").returncode, 0)
        self.assertEqual(self.edit(self.tmp / "loose.nix").returncode, 0)
        self.assertEqual(self.called(), "")

    def test_formatter_failure_reaches_claude(self):
        result = self.edit(self.repo / "bad.nix", FAIL_ALEJANDRA="1")
        self.assertEqual(result.returncode, 2)
        self.assertIn("alejandra: boom", result.stderr)

    def test_markdown_lint_only_where_configured(self):
        other = self.git_repo("plain")
        self.assertEqual(self.edit(other / "README.md").returncode, 0)
        self.assertEqual(self.called(), "")
        (self.repo / ".markdownlint.json").write_text("{}")
        result = self.edit(self.repo / "docs/x.md", FAIL_MARKDOWNLINT="1")
        self.assertEqual(result.returncode, 2)
        self.assertIn("markdownlint-cli2: boom", result.stderr)
        self.assertIn("docs/x.md", self.called())

    def test_missing_file_is_ignored(self):
        result = subprocess.run(
            [sys.executable, "-I", str(SCRIPTS / "format-on-edit")],
            input=json.dumps({"tool_input": {"file_path": str(self.repo / "gone.nix")}}),
            text=True, capture_output=True, env=self.env, check=False,
        )
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.called(), "")


if __name__ == "__main__":
    unittest.main()
