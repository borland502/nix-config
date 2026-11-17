#!/usr/bin/env python3
"""install.sh is the one bootstrap that runs before zsh exists, so it must stay bash-3.2-compatible."""
import re
import subprocess
import unittest
from pathlib import Path

INSTALL = Path(__file__).resolve().parents[1] / 'install.sh'
# Constructs bash 3.2 lacks or treats differently, with the reason.
BASH4_ONLY = {
    r'\bmapfile\b|\breadarray\b': 'bash 4 builtin',
    r'\bdeclare\s+-[a-zA-Z]*A|\blocal\s+-[a-zA-Z]*[An]|\btypeset\s+-[a-zA-Z]*A': 'associative array or nameref',
    r'\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^|,|\^)\}': 'case-modification expansion',
    r';;&|;&': 'case fall-through',
    r'\|&': 'pipe-stderr shorthand',
    r'\bcoproc\b': 'coproc',
    r'\$\{[A-Za-z_][A-Za-z0-9_]*\[@\]:': 'array slicing (empty-safe only on 4.4+)',
}


class InstallBootstrapContract(unittest.TestCase):
    def test_header_declares_the_contract(self):
        header = '\n'.join(INSTALL.read_text().splitlines()[:12])
        self.assertIn('bash 3.2', header)

    def test_no_bash4_only_constructs(self):
        code = '\n'.join(line for line in INSTALL.read_text().splitlines() if not line.lstrip().startswith('#'))
        found = [f'{why}: {m.group(0)}' for pattern, why in BASH4_ONLY.items() for m in re.finditer(pattern, code)]
        self.assertEqual(found, [])

    def test_every_array_expansion_has_a_nonempty_literal(self):
        code = INSTALL.read_text()
        for name in set(re.findall(r'"\$\{([A-Za-z_][A-Za-z0-9_]*)\[@\]\}"', code)):
            self.assertRegex(code, rf'(?m)^\s*{name}=\(\s*[^)\s]', f'{name} may be empty under set -u on bash 3.2')

    @unittest.skipUnless(Path('/bin/bash').exists(), 'needs /bin/bash')
    def test_parses_under_system_bash(self):
        result = subprocess.run(['/bin/bash', '-n', str(INSTALL)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_every_nix_shell_provides_zsh(self):
        # The tasks install.sh runs call zsh scripts (task switch, chezmoi apply),
        # and a fresh Linux or NixOS-WSL host has no zsh until the first switch.
        shells = re.findall(r'nix shell ([^\n]*?)--command', INSTALL.read_text())
        self.assertTrue(shells, 'expected nix shell invocations in install.sh')
        for packages in shells:
            self.assertIn('nixpkgs#zsh', packages, f'nix shell without zsh: {packages}')

    def test_repo_scripts_run_through_run_zsh(self):
        # Repo scripts are zsh. install.sh may run one only through _run_zsh, which
        # falls back to `nix shell nixpkgs#zsh` before the first switch provides zsh.
        code = INSTALL.read_text()
        self.assertEqual(re.findall(r'\bbash "\$_[a-z_]+"', code), [])
        self.assertRegex(code, r'(?m)^_run_zsh\(\) \{')
        for script in ('_bootstrap_win', '_provision_secrets'):
            self.assertIn(f'_run_zsh "${script}"', code)


if __name__ == '__main__':
    unittest.main()
