"""Offline reliability contracts for operational commands."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "chezmoi/dot_local/lib"
sys.path.insert(0, str(LIB))

def load_ops():
    spec = importlib.util.spec_from_file_location("ops", ROOT / "ai-tools/scripts/ops-agent.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

class Operations(unittest.TestCase):
    def setUp(self):
        self.ops = load_ops()

    def invoke(self, name, value):
        out, err = io.StringIO(), io.StringIO()
        rc = 0
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                self.ops._run_tool(name, value)
            except SystemExit as exc:
                rc = exc.code
        return rc, out.getvalue(), err.getvalue()

    def test_unknown_operation_fails_without_configuration(self):
        with patch.object(self.ops, "_require_secrets"):
            rc, out, err = self.invoke("missing", "{}")
        self.assertNotEqual(rc, 0)
        self.assertEqual(out, "")
        self.assertIn("unknown tool", err)

    def test_prompt_mode_pins_mid_tier_model_unless_overridden(self):
        for override, expected in ((None, "sonnet"), ("", "sonnet"), ("opus", "opus")):
            with self.subTest(override=override):
                env = {k: v for k, v in os.environ.items() if k != "OPS_AGENT_MODEL"}
                if override is not None:
                    env["OPS_AGENT_MODEL"] = override
                with patch.dict(os.environ, env, clear=True), \
                        patch.object(self.ops.shutil, "which", return_value="/fixture/claude"), \
                        patch.object(self.ops.os, "execv") as execv:
                    self.ops.run("fixture request")
                argv = execv.call_args.args[1]
                self.assertEqual(argv[argv.index("--model") + 1], expected)
                self.assertEqual(argv.count("--model"), 1)

    def test_invalid_input_is_diagnostic(self):
        for value in ('{"args": 1}', '{}', '[]', '{bad', '{"args":[1]}'):
            with self.subTest(value=value), patch.object(self.ops, "_require_secrets"):
                rc, out, err = self.invoke("aws_cli", value)
                self.assertNotEqual(rc, 0)
                self.assertTrue(err)
                self.assertEqual(out, "")

    def test_aws_nonzero_fails_and_no_jira_config_required(self):
        with patch.object(self.ops, "_kion_creds", return_value={}), patch("subprocess.run", return_value=subprocess.CompletedProcess(["aws"], 9, "", "fixture failure")):
            rc, out, err = self.invoke("aws_cli", '{"args":["fixture"]}')
        self.assertNotEqual(rc, 0)
        self.assertIn("fixture failure", err)
        self.assertEqual(out, "")

    def test_aws_success_output_is_preserved_without_unrelated_config(self):
        for text in ("plain output", "{partial text"):
            with self.subTest(text=text), patch.object(self.ops, "_kion_creds", return_value={}), patch("subprocess.run", return_value=subprocess.CompletedProcess(["aws"], 0, text, "")), patch.object(self.ops, "_require_secrets", side_effect=AssertionError("unrelated config")):
                rc, out, err = self.invoke("aws_cli", '{"args":["fixture"]}')
                self.assertEqual(rc, 0, err)
                self.assertEqual(out, text + "\n")

    def test_missing_chosen_configuration_fails_without_prompt(self):
        with patch.object(self.ops, "_SECRET_JIRA_URL", Path('/nonexistent/fixture')), patch("builtins.input", side_effect=AssertionError("must not prompt")):
            rc, out, err = self.invoke("jira_get_issue", '{"ticket_id":"TEST-1"}')
        self.assertNotEqual(rc, 0)
        self.assertIn("config", err.lower())
        self.assertEqual(out, "")

    def test_input_file_preserves_positional_interface(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "input.json"
            p.write_text('{"args":["fixture"]}')
            with patch.object(sys, "argv", ["ops-agent", "--tool", "aws_cli", "--input-file", str(p)]), patch.object(self.ops, "_run_tool") as run:
                self.ops.main()
                run.assert_called_once_with("aws_cli", p.read_text())

class Shared(unittest.TestCase):
    def test_checked_process_and_timeout(self):
        from agent_tools.process import run, ProcessError
        self.assertEqual(run([sys.executable, "-c", "print('ok')"]).stdout, "ok\n")
        for argv, timeout in [([sys.executable, "-c", "import sys;sys.stderr.write('failure');sys.exit(7)"], 5), ([sys.executable, "-c", "import time;time.sleep(1)"], .01), (["/nonexistent/fixture"], 5)]:
            with self.subTest(argv=argv), self.assertRaises(ProcessError) as exc:
                run(argv, timeout=timeout)
            self.assertLess(len(str(exc.exception)), 5000)

    def test_json_process_errors_and_timeout_type(self):
        from agent_tools.process import ProcessError, ProcessTimeout, run_json
        self.assertTrue(issubclass(ProcessTimeout, ProcessError))
        self.assertEqual(run_json([sys.executable, "-c", "print('[1, 2]')"]), [1, 2])
        for output in ("", "secret malformed response"):
            with self.subTest(output=output), self.assertRaises(ProcessError) as exc:
                run_json([sys.executable, "-c", f"print({output!r})"])
            self.assertEqual(str(exc.exception), "command returned malformed JSON")
        with self.assertRaises(ProcessTimeout) as exc:
            run_json([sys.executable, "-c", "import time; time.sleep(1)"], timeout=.01)
        self.assertEqual(str(exc.exception), "command timed out")
        for argv in (["/nonexistent/fixture"], [sys.executable, "-c", "import sys; sys.exit(7)"]):
            with self.subTest(argv=argv), self.assertRaises(ProcessError):
                run_json(argv)

    def test_private_atomic_publication(self):
        from agent_tools.artifacts import atomic_write
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "artifact"
            atomic_write(p, b"old", replace=False)
            self.assertEqual(stat.S_IMODE(p.stat().st_mode), 0o600)
            with self.assertRaises(FileExistsError):
                atomic_write(p, b"new", replace=False)
            self.assertEqual(p.read_bytes(), b"old")
            with self.assertRaises(TypeError):
                atomic_write(p, object(), replace=True)
            self.assertEqual(p.read_bytes(), b"old")
            atomic_write(p, b"new", replace=True)
            self.assertEqual(p.read_bytes(), b"new")
            self.assertEqual(list(Path(tmp).iterdir()), [p])

class HTTP(unittest.TestCase):
    def test_json_http_errors_are_bounded_and_sanitized(self):
        import urllib.error
        from agent_tools.atlassian import Client, AtlassianError
        class Body(io.BytesIO):
            def read(self, size=-1):
                self.requested = size
                return super().read(size)
        for body, included in [
            (b'{"message":"Bad fixture-token Authorization: Bearer abc123 password=secretvalue\\nnext", "errorMessages":["useful"], "errors":{"field":"invalid"}, "other":"hidden"}', True),
            (b'{\"message\":\"' + b'x' * 1000 + b'\"}', True),
            (b'<html>private</html>', False),
            (b'{broken', False),
        ]:
            with self.subTest(body=body):
                stream = Body(body)
                error = urllib.error.HTTPError('http://fixture.invalid', 400, 'bad', {}, stream)
                with patch('urllib.request.build_opener') as opener:
                    opener.return_value.open.side_effect = error
                    with self.assertRaises(AtlassianError) as exc:
                        Client('http://fixture.invalid', 'fixture-token').request('GET', 'fixture')
                message = str(exc.exception)
                self.assertEqual(getattr(stream, "requested", None), 8192)
                self.assertTrue(message.startswith('HTTP 400 on GET request'))
                self.assertNotIn('fixture-token', message)
                self.assertNotIn('abc123', message)
                self.assertNotIn('secretvalue', message)
                self.assertNotIn('hidden', message)
                self.assertNotIn('private', message)
                self.assertLessEqual(len(message), len('HTTP 400 on GET request: ') + 500)
                if b'errorMessages' in body:
                    self.assertIn('useful', message)
                    self.assertIn('invalid', message)
                elif not included:
                    self.assertEqual(message, 'HTTP 400 on GET request')

    def test_http_error_redacts_quoted_credentials_and_normalized_token(self):
        import json
        import urllib.error
        from agent_tools.atlassian import Client, AtlassianError
        messages = [
            'password="two words"',
            "'password': 'two words'",
            'Authorization: Bearer "two words"',
            'fixture-\u200btoken',
        ]
        for value in messages:
            with self.subTest(value=value):
                body = io.BytesIO(json.dumps({'message': value}).encode())
                error = urllib.error.HTTPError('http://fixture.invalid', 400, 'bad', {}, body)
                with patch('urllib.request.build_opener') as opener:
                    opener.return_value.open.side_effect = error
                    with self.assertRaises(AtlassianError) as exc:
                        Client('http://fixture.invalid', 'fixture-token').request('GET', 'fixture')
                self.assertNotIn('two', str(exc.exception))
                self.assertNotIn('words', str(exc.exception))
                self.assertNotIn('fixture-token', str(exc.exception))

    def test_http_error_redacts_prefixed_credential_names(self):
        import json
        import urllib.error
        from agent_tools.atlassian import Client, AtlassianError
        for key in ('access_token', 'refresh_token', 'client_secret', 'api_key', 'X-API-Key', 'accessToken', 'clientSecret', 'tokenValue', 'myCredentialValue', 'authorizationHeader', 'myApiKeyValue'):
            for quote in ('', '"', "'"):
                with self.subTest(key=key, quote=quote):
                    value = f'useful context {quote}{key}{quote}={quote}private-value{quote}'
                    body = io.BytesIO(json.dumps({'message': value}).encode())
                    error = urllib.error.HTTPError('http://fixture.invalid', 400, 'bad', {}, body)
                    with patch('urllib.request.build_opener') as opener:
                        opener.return_value.open.side_effect = error
                        with self.assertRaises(AtlassianError) as exc:
                            Client('http://fixture.invalid', 'fixture-token').request('GET', 'fixture')
                    self.assertNotIn('private-value', str(exc.exception))
                    self.assertIn('useful context', str(exc.exception))

    def test_truncated_response_has_typed_bounded_error_and_clean_cli_failure(self):
        import http.server
        import threading
        from agent_tools.atlassian import Client, AtlassianError
        requests = []
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append(self.path)
                self.send_response(200)
                self.send_header("Content-Length", "100")
                self.end_headers()
                self.wfile.write(b'{"ok":')
                self.close_connection = True
            def log_message(self, *args):
                pass
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        root = f"http://127.0.0.1:{server.server_port}"
        try:
            with self.subTest(caller="client"):
                with self.assertRaises(AtlassianError) as exc:
                    Client(root, "fixture-token").request("GET", "fixture")
                self.assertEqual(str(exc.exception), "service request failed or timed out")
            with self.subTest(caller="jira-get"), tempfile.TemporaryDirectory() as tmp:
                config = Path(tmp) / ".config/ops-agent"
                config.mkdir(parents=True)
                (config / "jira-base-url").write_text(root)
                (config / "jira-token").write_text("fixture-token")
                result = subprocess.run([sys.executable, str(ROOT / "chezmoi/dot_local/bin/executable_jira-get"), "fixture"], env=dict(os.environ, HOME=tmp, AGENT_TOOLS_LIB=str(LIB)), capture_output=True, text=True)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")
                self.assertEqual(result.stderr, "jira-get: service request failed or timed out\n")
            self.assertEqual(requests, ["/fixture", "/fixture"])
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_shared_get_adapter_accepts_explicit_argv_and_prog(self):
        from agent_tools.atlassian_cli import get_main
        with patch("agent_tools.atlassian_cli.Client.configured") as configured:
            configured.return_value.request.return_value = b'{"ok":true}'
            output = io.TextIOWrapper(io.BytesIO(), encoding="utf-8")
            with contextlib.redirect_stdout(output):
                rc = get_main("jira", argv=["fixture"], prog="custom-get")
            output.flush()
            self.assertEqual(output.buffer.getvalue(), b'{"ok":true}')
            self.assertEqual(rc, 0)
            configured.assert_called_once_with("jira")
            configured.return_value.request.assert_called_once_with("GET", "fixture", return_raw=True)
        help_output = io.StringIO()
        with contextlib.redirect_stdout(help_output), self.assertRaises(SystemExit) as exc:
            get_main("jira", argv=["--help"], prog="custom-get")
        self.assertEqual(exc.exception.code, 0)
        self.assertIn("usage: custom-get", help_output.getvalue())

    def test_get_help_and_argument_errors_need_no_configuration(self):
        with tempfile.TemporaryDirectory() as tmp:
            for service in ("jira", "confluence"):
                script = ROOT / f"chezmoi/dot_local/bin/executable_{service}-get"
                env = dict(os.environ, HOME=tmp, AGENT_TOOLS_LIB=str(LIB))
                for args, expected in ((["--help"], 0), ([], 2)):
                    with self.subTest(service=service, args=args):
                        result = subprocess.run([sys.executable, str(script), *args], env=env, capture_output=True)
                        self.assertEqual(result.returncode, expected)
                        output = result.stdout if expected == 0 else result.stderr
                        self.assertIn(f"usage: executable_{service}-get".encode(), output)
                        if expected == 0:
                            self.assertIn(b"GET a configured Atlassian API path and validate the JSON response.", output)
                        else:
                            self.assertIn(b"the following arguments are required: path", output)

    def test_real_get_parsers(self):
        # Run the actual commands with isolated configuration and a loopback fixture.
        import http.server
        import threading
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(503 if self.path.endswith('error') else 200)
                self.end_headers()
                self.wfile.write({"good": b' \n{"ok":true}', "bad": b'{broken', "html": b'<html>bad</html>', "empty": b'', "error": b'<html>unavailable</html>'}[self.path.rsplit('/', 1)[-1]])
            def log_message(self, *args):
                pass
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as tmp:
                home = Path(tmp)
                for service, directory, base, token in [('jira', 'ops-agent', 'jira-base-url', 'jira-token'), ('confluence', 'confluence', 'base-url', 'token')]:
                    cfg = home / '.config' / directory
                    cfg.mkdir(parents=True)
                    (cfg / base).write_text(f'http://127.0.0.1:{server.server_port}')
                    (cfg / token).write_text('fixture-token')
                    for case in ('good', 'bad', 'html', 'empty', 'error'):
                        with self.subTest(service=service, case=case):
                            script = ROOT / f'chezmoi/dot_local/bin/executable_{service}-get'
                            interpreter = script.read_text().splitlines()[0].removeprefix('#!').split()
                            p = subprocess.run([*interpreter, str(script), case], env=dict(os.environ, HOME=tmp, PYTHONPATH=str(LIB)), capture_output=True)
                            self.assertEqual(p.returncode, 0 if case == 'good' else 1, p.stderr)
                            if case == 'good':
                                self.assertEqual(p.stdout, b' \n{"ok":true}')
                            else:
                                self.assertEqual(p.stdout, b'')
                                self.assertTrue(p.stderr.startswith(f'{service}-get: '.encode()))
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_pagination_follows_same_service_links(self):
        from agent_tools.atlassian import Client
        client = Client("http://fixture.invalid/rest/api", "fixture-token")
        with patch.object(client, "request", side_effect=[
            {"results": [1], "_links": {"next": "/rest/api/content?page=2"}},
            {"results": [2], "_links": {}}]) as request:
            self.assertEqual([p["results"] for p in client.pages("content?page=1")], [[1], [2]])
            self.assertEqual(request.call_args.args, ("GET", "http://fixture.invalid/rest/api/content?page=2"))

    def test_ops_http_errors_propagate_to_nonzero(self):
        from agent_tools.atlassian import AtlassianError
        ops = load_ops()
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / "fixture"
            config.write_text("fixture")
            with patch.object(ops, "_SECRET_JIRA_URL", config), patch.object(ops, "_SECRET_JIRA_TOKEN", config), patch.object(ops, "_jira_request", side_effect=AtlassianError("HTTP 503")), contextlib.redirect_stderr(io.StringIO()) as err, contextlib.redirect_stdout(io.StringIO()) as out, self.assertRaises(SystemExit) as exc:
                ops._run_tool("jira_get_issue", '{"ticket_id":"TEST-1"}')
            self.assertEqual(exc.exception.code, 1)
            self.assertIn("HTTP 503", err.getvalue())
            self.assertEqual(out.getvalue(), "")

    def test_store_file_uses_explicit_library_override(self):
        import shutil
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "ops-agent.py"
            shutil.copyfile(ROOT / "ai-tools/scripts/ops-agent.py", source)
            env = dict(os.environ, HOME=tmp, AGENT_TOOLS_LIB=str(LIB))
            env.pop("PYTHONPATH", None)
            result = subprocess.run([sys.executable, str(source), "--tool", "missing", "{}"], capture_output=True, text=True, env=env)
            self.assertEqual(result.returncode, 1)
            self.assertIn("unknown tool", result.stderr)
            self.assertNotIn("Traceback", result.stderr)

    def test_pagination_refuses_external_and_cycles(self):
        from agent_tools.atlassian import Client, AtlassianError
        client = Client('http://fixture.invalid/rest/api', 'fixture-token')
        for nxt in ('https://other.invalid/rest/api/content', '//other.invalid/content', '/outside', '?page=1'):
            with self.subTest(nxt=nxt):
                with patch.object(client, 'request', return_value={'results': [], '_links': {'next': nxt}}), self.assertRaises(AtlassianError):
                    list(client.pages('content?page=1'))

if __name__ == '__main__':
    unittest.main()
