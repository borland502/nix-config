#!/usr/bin/env python3
"""Discovery must include extensionless sources without linting nested dependencies."""
import importlib.util
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/lint-shell.py'


class DiscoveryTests(unittest.TestCase):
    def test_shebangs_and_safe_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            subprocess.run(['git', 'init', '-q', tmp], check=True)
            fixtures = {
                'chezmoi/dot_local/bin/executable_with space': '#!/usr/bin/env bash\necho ok\n',
                'ai-tools/scripts/hook': '#!/bin/sh\necho ok\n',
                'zsh-helper': '#!/bin/zsh\nprint ok\n',
                'env-s': '#!/usr/bin/env -S bash -e\necho ok\n',
                'node_modules/skip': '#!/bin/bash\n',
                'template.sh.tmpl': '#!/bin/bash\n{{ value }}\n',
                'python': '#!/usr/bin/env python3\n',
            }
            for name, content in fixtures.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
            result = subprocess.run(['python3', str(SCRIPT), '--root', tmp, '--list'],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout), {
                'ai-tools/scripts/hook': 'sh',
                'chezmoi/dot_local/bin/executable_with space': 'bash',
                'env-s': 'bash', 'zsh-helper': 'zsh',
            })


_spec = importlib.util.spec_from_file_location('lint_shell', SCRIPT)
lint_shell = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(lint_shell)


class AllowlistTests(unittest.TestCase):
    def test_load_allowlist_ignores_comments_and_blanks(self):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / 'scripts').mkdir()
            (Path(tmp) / 'scripts/bash-allowlist.txt').write_text(
                '# header\n\ninstall.sh  # permanent bootstrap\nscripts/legacy.sh\n')
            self.assertEqual(lint_shell.load_allowlist(Path(tmp)), {'install.sh', 'scripts/legacy.sh'})

    def test_bash_outside_allowlist_is_a_violation(self):
        scripts = {'install.sh': 'bash', 'new-helper': 'bash', 'z': 'zsh', 'hook': 'sh'}
        self.assertEqual(lint_shell.bash_violations(scripts, {'install.sh'}), ['new-helper'])


@unittest.skipUnless(shutil.which('zsh') and shutil.which('shfmt'), 'needs zsh and shfmt')
class ZshFormatTests(unittest.TestCase):
    def _run(self, content):
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run(['git', 'init', '-q', tmp], check=True)
            (Path(tmp) / 'scripts').mkdir()
            (Path(tmp) / 'scripts/bash-allowlist.txt').write_text('')
            (Path(tmp) / 'helper').write_text(content)
            return subprocess.run(['python3', str(SCRIPT), '--root', tmp, '--format'],
                                  capture_output=True, text=True)

    def test_misformatted_zsh_fails(self):
        self.assertNotEqual(self._run('#!/usr/bin/env -S zsh -f\nif true; then\n    print ok\nfi\n').returncode, 0)

    def test_formatted_zsh_passes(self):
        result = self._run('#!/usr/bin/env -S zsh -f\nif true; then\n\tprint ok\nfi\n')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
