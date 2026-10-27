#!/usr/bin/env python3
"""Exercise real query orchestration with a deterministic GitHub boundary."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'chezmoi/dot_local/bin/executable_gh-pr-threads'


class ContextTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        fake = self.base / 'gh-graphql'
        fake.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
query = Path(args[1]).name
variables = dict(x.split('=', 1) for x in args[2:] if '=' in x)
with open(os.environ['TRACE'], 'a') as f: f.write(json.dumps([query, variables]) + '\\n')
def conn(nodes, more=False):
    return {'nodes': nodes, 'pageInfo': {'hasNextPage': more, 'endCursor': 'next' if more else None}}
def comment(body):
    return {'id': body, 'databaseId': 1, 'body': body, 'createdAt': '2026-10-01T00:00:00Z', 'url': 'https://example.invalid/comment', 'author': {'login': 'alice'}}
if os.environ.get('GRAPHQL_ERROR'):
    print('{"errors":[{"message":"denied"}]}'); sys.exit(0)
if query == 'review-threads.graphql':
    second = bool(variables.get('cursor'))
    thread = {'id': 'thread2' if second else 'thread1', 'isResolved': second, 'isOutdated': False, 'path': 'src/a.py', 'line': 4, 'comments': conn([comment('opening')], not second)}
    payload = {'repository': {'pullRequest': {'reviewThreads': conn([thread], not second)}}}
elif query == 'thread-comments.graphql':
    payload = {'node': {'comments': conn([comment('reply')])}}
elif query == 'pr-comments.graphql':
    second = bool(variables.get('cursor'))
    payload = {'repository': {'pullRequest': {'comments': conn([comment('discussion2' if second else 'discussion')], not second)}}}
elif query == 'pr-reviews.graphql':
    second = bool(variables.get('cursor'))
    payload = {'repository': {'pullRequest': {'reviews': conn([dict(comment('review2' if second else 'review'), state='COMMENTED', submittedAt='2026-10-01T00:00:00Z')], not second)}}}
else: raise SystemExit('unknown query ' + query)
print(json.dumps({'data': payload}))
''')
        fake.chmod(0o755)
        self.env = dict(os.environ, PATH=f'{self.base}:{os.environ["PATH"]}',
                        TRACE=str(self.base / 'trace'),
                        GH_PR_THREADS_DATA_DIR=str(ROOT / 'chezmoi/dot_local/share/gh-pr-threads'))

    def run_helper(self, *args):
        return subprocess.run([str(HELPER), '42', '--repo', 'example/project', *args],
                              env=self.env, capture_output=True, text=True, timeout=10)

    def test_paginated_context(self):
        result = self.run_helper('--all', '--context', '--json')
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(len(payload['threads']), 2)
        self.assertEqual([c['body'] for c in payload['threads'][0]['comments']], ['opening', 'reply'])
        self.assertEqual(len(payload['comments']), 2)
        self.assertEqual(len(payload['reviews']), 2)
        self.assertEqual(payload['threads'][0]['id'], 'thread1')
        self.assertIn('createdAt', payload['threads'][0]['comments'][0])

    def test_default_shape_filters_and_pagination(self):
        result = self.run_helper('--json', '--author', 'alice')
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(len(payload), 1)
        self.assertEqual(set(payload[0]), {'resolved', 'outdated', 'path', 'line', 'author', 'body', 'url'})
        self.assertIn('"cursor": "next"', (self.base / 'trace').read_text())

    def test_graphql_error_is_not_empty_success(self):
        self.env['GRAPHQL_ERROR'] = '1'
        result = self.run_helper('--json')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('denied', result.stderr)


if __name__ == '__main__':
    unittest.main()
