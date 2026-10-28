#!/usr/bin/env python3
"""Offline contract tests for CI job waiting and passive monitoring."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "chezmoi/dot_local/bin"


class WaitingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        gh = self.base / "gh"
        gh.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
with open(os.environ['TRACE'], 'a') as f: f.write(' '.join(sys.argv[1:]) + '\\n')
if os.environ.get('API_FAIL'): sys.exit(2)
if sys.argv[1:3] == ['run', 'list']:
    print('[{"databaseId": 123, "status": "in_progress"}, {"databaseId": 124, "status": "queued"}]')
elif sys.argv[1:3] == ['run', 'cancel']:
    print('Cancellation requested')
elif sys.argv[3] == '124':
    print('{"status":"completed","conclusion":"success","jobs":[]}')
else:
    print(os.environ['SNAPSHOT'])
''')
        gh.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{self.base}:{os.environ['PATH']}",
                        TRACE=str(self.base / "trace"))

    def run_wait(self, snapshot, *args, monitor=False):
        self.env['SNAPSHOT'] = json.dumps(snapshot)
        name = "executable_monitor-gh-run" if monitor else "executable_gh-wait-job"
        return subprocess.run([str(BIN / name), "123", *args], env=self.env,
                              text=True, capture_output=True, timeout=5)

    def test_only_success_is_success(self):
        for conclusion in ('success', 'failure', 'cancelled', 'skipped', 'timed_out', 'neutral'):
            with self.subTest(conclusion=conclusion):
                result = self.run_wait({'status': 'completed', 'jobs': [
                    {'name': 'Deploy', 'status': 'completed', 'conclusion': conclusion}]},
                    '--job', 'Deploy', '--repo', 'example/project')
                self.assertEqual(result.returncode, 0 if conclusion == 'success' else 1, result.stderr)

    def test_completed_workflow_without_job_fails(self):
        result = self.run_wait({'status': 'completed', 'jobs': []}, '--job', 'Deploy')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('not found', result.stderr)

    def test_job_success_before_workflow_completion(self):
        result = self.run_wait({'status': 'in_progress', 'jobs': [
            {'name': 'Deploy', 'status': 'completed', 'conclusion': 'success'}]}, '--job', 'Deploy')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_timeout(self):
        result = self.run_wait({'status': 'in_progress', 'jobs': []}, '--job', 'Deploy',
                               '--timeout', '0', '--interval', '1')
        self.assertEqual(result.returncode, 124, result.stderr)

    def test_api_failure_and_invalid_input(self):
        self.env['API_FAIL'] = '1'
        self.assertNotEqual(self.run_wait({}, '--job', 'Deploy').returncode, 0)
        self.assertEqual(self.run_wait({}, '--job', 'Deploy', '--timeout', '-1').returncode, 64)

    def test_monitor_is_passive_by_default(self):
        result = self.run_wait({'status': 'completed', 'conclusion': 'success',
            'headBranch': 'feature', 'workflowName': 'CI', 'name': 'CI', 'jobs': []}, monitor=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        trace = (self.base / 'trace').read_text()
        self.assertNotIn('run cancel', trace)
        self.assertNotIn('run list', trace)

    def test_monitor_cancels_only_with_explicit_flag(self):
        result = self.run_wait({'status': 'in_progress', 'conclusion': '',
            'headBranch': 'feature', 'workflowName': 'CI', 'jobs': []},
            '--cancel-duplicates', monitor=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        trace = (self.base / 'trace').read_text()
        self.assertIn('run cancel 123', trace)
        self.assertIn('run view 124', trace)
        self.assertNotIn('run cancel 124', trace)

    def test_monitor_supports_job_and_repo(self):
        result = self.run_wait({'status': 'in_progress', 'jobs': [
            {'name': 'Deploy', 'status': 'completed', 'conclusion': 'success'}]},
            '--job', 'Deploy', '--repo', 'example/project', monitor=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--repo example/project', (self.base / 'trace').read_text())


if __name__ == '__main__':
    unittest.main()
