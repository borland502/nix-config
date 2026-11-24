"""Offline end-to-end contracts for the Confluence page CLI."""
import http.server
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'chezmoi/dot_local/bin/executable_confluence-page'
LIB = ROOT / 'chezmoi/dot_local/lib'


class CLI(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.requests = []
        self.page_body = '<p>original</p>'
        owner = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def respond(self, method):
                data = self.rfile.read(int(self.headers.get('Content-Length', 0)))
                owner.requests.append((method, self.path, data))
                if method == 'PUT':
                    result = {'id': '123', 'version': {'number': 12}}
                    code = owner.put_status
                elif method == 'POST':
                    result = {'results': [{'id': 'new-id', 'version': {'number': 1}}]}
                    code = 200
                elif '/child/' in self.path:
                    page2 = 'page=2' in self.path
                    is_attachment = '/attachment' in self.path
                    result = {'results': ([{'id': 'old-id', 'title': 'old.txt', 'version': {'number': 2}}] if page2 else []) if is_attachment else [{'id': '2' if page2 else '1', 'title': 'Second' if page2 else 'First', 'version': {'number': 1}}]}
                    if not page2:
                        result['_links'] = {'next': self.path.split('?')[0] + '?page=2'}
                    code = 200
                else:
                    result = {'id': '123', 'title': 'Fixture page', 'space': {'key': 'FIX'}, 'version': {'number': 11}, 'ancestors': [{'id': '9'}], 'body': {'storage': {'value': owner.page_body}}}
                    code = 200
                self.send_response(code)
                self.end_headers()
                self.wfile.write(json.dumps(result).encode())

            def do_GET(self): self.respond('GET')
            def do_PUT(self): self.respond('PUT')
            def do_POST(self): self.respond('POST')
            def log_message(self, *args): pass

        self.put_status = 200
        self.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.thread.join)
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        config = Path(self.tmp.name) / '.config/confluence'
        config.mkdir(parents=True)
        (config / 'base-url').write_text(f'http://127.0.0.1:{self.server.server_port}')
        (config / 'token').write_text('fixture-token')

    def invoke(self, *args):
        return subprocess.run([sys.executable, str(SCRIPT), *map(str, args)], env=dict(os.environ, HOME=self.tmp.name, AGENT_TOOLS_LIB=str(LIB)), capture_output=True, text=True)

    def body(self, text):
        path = Path(self.tmp.name) / 'body'
        path.write_text(text, newline='')
        return path

    def test_body_update_requires_matching_version_and_rejects_blank(self):
        for options in ([], ['--expected-version', '10'], ['--expected-version', '0'], ['--expected-version', 'bad']):
            with self.subTest(options=options):
                self.requests.clear()
                result = self.invoke('update', '123', '--body-file', self.body('<p>draft</p>'), *options)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(result.stderr)
                self.assertFalse(any(r[0] == 'PUT' for r in self.requests))
        for extra in ([], ['--dry-run']):
            self.requests.clear()
            result = self.invoke('update', '123', '--body-file', self.body(' \n\t'), '--expected-version', '11', *extra)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(any(r[0] == 'PUT' for r in self.requests))
        for extra in ([], ['--dry-run']):
            self.requests.clear()
            result = self.invoke('update', '123', '--body-file', self.body('draft'), '--expected-version', '10', *extra)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('version', result.stderr)
            self.assertFalse(any(r[0] == 'PUT' for r in self.requests))
        self.requests.clear()
        result = self.invoke('update', '123', '--title', 'New', '--expected-version', '10')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(r[0] == 'PUT' for r in self.requests))

    def test_matching_update_preserves_metadata_and_body_bytes(self):
        replacement = '  <p>draft</p>\r\n'
        result = self.invoke('update', '123', '--body-file', self.body(replacement), '--expected-version', '11')
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(next(r[2] for r in self.requests if r[0] == 'PUT'))
        self.assertEqual(payload['version']['number'], 12)
        self.assertEqual(payload['body']['storage']['value'], replacement)
        self.assertEqual(payload['title'], 'Fixture page')
        self.assertEqual(payload['space']['key'], 'FIX')
        self.assertEqual(payload['ancestors'], [{'id': '9'}])

    def test_metadata_update_preserves_nonempty_whitespace_body(self):
        self.page_body = ' \n\t'
        result = self.invoke('update', '123', '--title', 'Renamed')
        self.assertEqual(result.returncode, 0, result.stderr)
        puts = [r for r in self.requests if r[0] == 'PUT']
        self.assertEqual(len(puts), 1)
        payload = json.loads(puts[0][2])
        self.assertEqual(payload['body']['storage']['value'], self.page_body)
        self.assertEqual(payload['title'], 'Renamed')

    def test_metadata_update_preserves_body_and_conflict_is_not_retried(self):
        self.put_status = 409
        result = self.invoke('update', '123', '--title', 'Renamed')
        self.assertNotEqual(result.returncode, 0)
        puts = [r for r in self.requests if r[0] == 'PUT']
        self.assertEqual(len(puts), 1)
        self.assertEqual(json.loads(puts[0][2])['body']['storage']['value'], '<p>original</p>')

    def test_paginated_listings_and_limit_validation(self):
        result = self.invoke('children', '123', '--limit', '1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('First', result.stdout)
        self.assertIn('Second', result.stdout)
        result = self.invoke('attachments', '123')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('old.txt', result.stdout)
        self.assertNotEqual(self.invoke('children', '123', '--limit', '0').returncode, 0)

    def test_attachment_discovery_and_repeated_names(self):
        first = Path(self.tmp.name) / 'one' / 'same.txt'
        second = Path(self.tmp.name) / 'two' / 'same.txt'
        old = Path(self.tmp.name) / 'old.txt'
        for p in (first, second, old):
            p.parent.mkdir(exist_ok=True)
            p.write_text('fixture')
        result = self.invoke('attach', '123', old, first, second)
        self.assertEqual(result.returncode, 0, result.stderr)
        paths = [r[1] for r in self.requests if r[0] == 'POST']
        self.assertEqual(paths, ['/rest/api/content/123/child/attachment/old-id/data', '/rest/api/content/123/child/attachment', '/rest/api/content/123/child/attachment/new-id/data'])
        self.requests.clear()
        self.assertEqual(self.invoke('attach', '123', first, '--dry-run').returncode, 0)
        self.assertFalse(any(r[0] == 'POST' for r in self.requests))


if __name__ == '__main__':
    unittest.main()
