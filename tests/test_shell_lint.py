#!/usr/bin/env python3
"""Discovery must include extensionless sources without linting nested dependencies."""
import json
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


if __name__ == '__main__':
    unittest.main()
