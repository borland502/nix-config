import contextlib
import fcntl
import importlib.machinery
import importlib.util
import io
import json
import os
import pathlib
import tempfile
import unittest
from unittest.mock import Mock, patch


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT_PATH = (
    REPOSITORY_ROOT
    / "chezmoi"
    / "dot_local"
    / "bin"
    / "private_executable_kion-aws-refresh"
)
ORIGINAL_CREDENTIALS = {
    "access_key": "original-access",
    "secret_access_key": "original-secret",
    "session_token": "original-token",
}
NEW_CREDENTIALS = {
    "access_key": "fixture-access",
    "secret_access_key": "fixture-secret",
    "session_token": "fixture-token",
}
NEWER_CREDENTIALS = {
    "access_key": "newer-access",
    "secret_access_key": "newer-secret",
    "session_token": "newer-token",
}


def load_module():
    loader = importlib.machinery.SourceFileLoader("kion_aws_refresh", str(SCRIPT_PATH))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class FakeResponse:
    def __init__(self, status, body):
        self.status = status
        self.body = body

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        return False

    def read(self):
        return json.dumps(self.body).encode("utf-8")


class FailingWriter:
    def __init__(self, descriptor):
        self.descriptor = descriptor

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        os.close(self.descriptor)
        return False

    def write(self, value):
        raise OSError("simulated credential write failure")


class KionAwsRefreshTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_module()

    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory(dir=REPOSITORY_ROOT)
        self.home_dir = pathlib.Path(self.temporary_directory.name)
        self.kion_path = self.home_dir / ".kion.yml"
        self.gkion_path = self.home_dir / ".config" / "gkion" / "config.toml"
        self.gkion_path.parent.mkdir(parents=True)
        self.cache_dir = self.home_dir / ".cache" / "kion-aws-cache"

    def tearDown(self):
        self.temporary_directory.cleanup()

    def settings(self, url, api_key, account, alias, car, load=True):
        self.kion_path.write_text(
            f"kion:\n  url: {url}\n  api_key: {api_key}\n", encoding="utf-8"
        )
        self.gkion_path.write_text(
            "\n".join(
                (
                    "[target]",
                    f'account = "{account}"',
                    f'alias = "{alias}"',
                    f'cloud_access_role = "{car}"',
                    "",
                )
            ),
            encoding="utf-8",
        )
        if load:
            return self.module.load_settings(self.kion_path, self.gkion_path)

    def cache_state_paths(self, cache_dir=None):
        cache_dir = cache_dir or self.cache_dir
        return (
            cache_dir.parent / f".{cache_dir.name}.legacy",
            cache_dir.parent / f".{cache_dir.name}.pending",
        )

    def cache_lock_path(self, cache_dir=None):
        cache_dir = cache_dir or self.cache_dir
        return cache_dir.parent / f".{cache_dir.name}.lock"

    def create_physical_cache(self, path, credentials):
        path.mkdir(parents=True)
        os.chmod(path, 0o700)
        for credential_key, filename in self.module.CACHE_FILES.items():
            if credential_key not in credentials:
                continue
            credential_path = path / filename
            credential_path.write_text(credentials[credential_key], encoding="utf-8")
            os.chmod(credential_path, 0o600)

    def create_generation(self, label, credentials, publish=False, complete=True):
        generation = (
            self.cache_dir.parent / f".{self.cache_dir.name}.generation-{label}"
        )
        generation.parent.mkdir(parents=True, exist_ok=True)
        values = (
            credentials
            if complete
            else {
                "access_key": credentials["access_key"],
                "secret_access_key": credentials["secret_access_key"],
            }
        )
        self.create_physical_cache(generation, values)
        if publish:
            os.symlink(generation.name, self.cache_dir)
        return generation

    def read_cache(self, cache_dir=None):
        cache_dir = cache_dir or self.cache_dir
        return {
            credential_key: (cache_dir / filename).read_text(encoding="utf-8")
            for credential_key, filename in self.module.CACHE_FILES.items()
        }

    def assert_usable_cache(self, expected, cache_dir=None):
        cache_dir = cache_dir or self.cache_dir
        self.assertTrue(cache_dir.exists())
        self.assertEqual(self.read_cache(cache_dir), expected)

    def assert_private_generation(self, expected):
        self.assertTrue(self.cache_dir.is_symlink())
        target = self.cache_dir.parent / os.readlink(self.cache_dir)
        self.assertTrue(target.is_dir())
        self.assertEqual(target.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.read_cache(), expected)
        for filename in self.module.CACHE_FILES.values():
            credential_path = target / filename
            self.assertFalse(credential_path.is_symlink())
            self.assertEqual(credential_path.stat().st_mode & 0o777, 0o600)

    def test_request_uses_car_endpoint_and_atomically_writes_private_cache(self):
        settings = self.settings(
            "https://cloudtamer.example.test",
            "fixture-app-key",
            "123456789012",
            "",
            "fixture-car",
        )
        opener = Mock(
            return_value=FakeResponse(
                201,
                {
                    "status": 201,
                    "data": NEW_CREDENTIALS,
                },
            )
        )

        credentials = self.module.request_credentials(*settings, opener=opener)
        self.module.write_cache(self.cache_dir, credentials)

        request = opener.call_args.args[0]
        self.assertEqual(
            request.full_url,
            "https://cloudtamer.example.test"
            "/api/v3/temporary-credentials/cloud-access-role",
        )
        self.assertEqual(request.get_method(), "POST")
        self.assertEqual(
            json.loads(request.data),
            {
                "account_number": "123456789012",
                "account_alias": "",
                "cloud_access_role_name": "fixture-car",
            },
        )
        self.assertEqual(request.get_header("Accept"), "application/json")
        self.assertEqual(request.get_header("Content-type"), "application/json")
        self.assertEqual(request.get_header("Authorization"), "Bearer fixture-app-key")
        self.assertEqual(request.get_header("Kion-source"), "kion-aws-refresh")
        opener.assert_called_once_with(request, timeout=30)
        self.assert_private_generation(NEW_CREDENTIALS)

    def test_load_settings_normalizes_host_only_url(self):
        settings = self.settings(
            "cloudtamer.example.test",
            "fixture-app-key",
            "123456789012",
            "fixture-alias",
            "fixture-car",
        )

        self.assertEqual(
            settings,
            (
                "https://cloudtamer.example.test",
                "fixture-app-key",
                "123456789012",
                "fixture-alias",
                "fixture-car",
            ),
        )

    def test_load_settings_uses_target_table(self):
        self.kion_path.write_text(
            "kion:\n  url: cloudtamer.example.test\n  api_key: fixture-app-key\n",
            encoding="utf-8",
        )
        self.gkion_path.write_text(
            "\n".join(
                (
                    'account = "wrong-top-level-account"',
                    'alias = "wrong-top-level-alias"',
                    'cloud_access_role = "wrong-top-level-car"',
                    "",
                    "[target]",
                    'account = "123456789012"',
                    'alias = "fixture-alias"',
                    'cloud_access_role = "fixture-car"',
                    "",
                )
            ),
            encoding="utf-8",
        )

        self.assertEqual(
            self.module.load_settings(self.kion_path, self.gkion_path),
            (
                "https://cloudtamer.example.test",
                "fixture-app-key",
                "123456789012",
                "fixture-alias",
                "fixture-car",
            ),
        )

    def favorites_settings(self, favorite):
        """gkion's real shape: [target] names a favorite, values live in .kion.yml."""
        self.kion_path.write_text(
            "\n".join(
                (
                    "kion:",
                    "  url: cloudtamer.example.test",
                    "  api_key: fixture-app-key",
                    "favorites:",
                    "    # Set cloud_access_role to the role you can assume.",
                    "  - name: mdp-old",
                    "    account: 999999999999",
                    "    cloud_access_role: Old Admin",
                    "  - name: mdp-dev",
                    "    account: 123456789012",
                    "    cloud_access_role: MDP Developer Admin",
                    "",
                )
            ),
            encoding="utf-8",
        )
        self.gkion_path.write_text(
            "\n".join(
                (
                    "[target]",
                    f'favorite = "{favorite}"',
                    'account = ""',
                    'alias = ""',
                    'cloud_access_role = ""',
                    "",
                )
            ),
            encoding="utf-8",
        )

    def test_load_settings_resolves_empty_target_from_named_favorite(self):
        self.favorites_settings("mdp-dev")

        self.assertEqual(
            self.module.load_settings(self.kion_path, self.gkion_path),
            (
                "https://cloudtamer.example.test",
                "fixture-app-key",
                "123456789012",
                "",
                "MDP Developer Admin",
            ),
        )

    def test_load_settings_prefers_populated_target_over_favorite(self):
        self.favorites_settings("mdp-dev")
        self.gkion_path.write_text(
            "\n".join(
                (
                    "[target]",
                    'favorite = "mdp-dev"',
                    'account = "555555555555"',
                    'alias = "explicit-alias"',
                    'cloud_access_role = "Explicit Role"',
                    "",
                )
            ),
            encoding="utf-8",
        )

        self.assertEqual(
            self.module.load_settings(self.kion_path, self.gkion_path),
            (
                "https://cloudtamer.example.test",
                "fixture-app-key",
                "555555555555",
                "explicit-alias",
                "Explicit Role",
            ),
        )

    def test_load_settings_rejects_favorite_with_no_matching_entry(self):
        self.favorites_settings("mdp-missing")

        with self.assertRaises(self.module.RefreshError):
            self.module.load_settings(self.kion_path, self.gkion_path)

    def test_load_settings_rejects_missing_api_key_or_cloud_access_role(self):
        for api_key, car in (("", "fixture-car"), ("fixture-app-key", "")):
            with self.subTest(api_key=api_key, car=car):
                self.settings(
                    "cloudtamer.example.test",
                    api_key,
                    "123456789012",
                    "fixture-alias",
                    car,
                    load=False,
                )
                with self.assertRaises(self.module.RefreshError):
                    self.module.load_settings(self.kion_path, self.gkion_path)

    def test_load_settings_rejects_insecure_url(self):
        self.settings(
            "http://cloudtamer.example.test",
            "fixture-app-key",
            "123456789012",
            "fixture-alias",
            "fixture-car",
            load=False,
        )

        with self.assertRaises(self.module.RefreshError):
            self.module.load_settings(self.kion_path, self.gkion_path)

    def test_request_rejects_non_success_or_malformed_response(self):
        responses = (
            FakeResponse(
                500,
                {
                    "status": 201,
                    "data": NEW_CREDENTIALS,
                },
            ),
            FakeResponse(
                201, {"status": 201, "data": {"access_key": "fixture-access"}}
            ),
        )

        for response in responses:
            with self.subTest(response=response.body):
                with self.assertRaises(self.module.RefreshError):
                    self.module.request_credentials(
                        "https://cloudtamer.example.test",
                        "fixture-app-key",
                        "123456789012",
                        "",
                        "fixture-car",
                        opener=Mock(return_value=response),
                    )

    def test_main_never_outputs_credentials_or_exports(self):
        self.settings(
            "cloudtamer.example.test",
            "fixture-app-key",
            "123456789012",
            "fixture-alias",
            "fixture-car",
            load=False,
        )
        cases = (
            (
                "success",
                FakeResponse(201, {"status": 201, "data": NEW_CREDENTIALS}),
                0,
                "completed",
            ),
            (
                "failure",
                FakeResponse(500, {"status": 500, "data": NEW_CREDENTIALS}),
                1,
                "failed",
            ),
        )

        for name, response, expected_status, expected_message in cases:
            with self.subTest(name=name):
                output = io.StringIO()
                opener = Mock(return_value=response)
                with (
                    patch.object(
                        self.module.pathlib.Path,
                        "home",
                        return_value=self.home_dir,
                    ),
                    patch.object(
                        self.module.request_credentials,
                        "__defaults__",
                        (opener,),
                    ),
                    contextlib.redirect_stdout(output),
                    contextlib.redirect_stderr(output),
                ):
                    self.assertEqual(self.module.main(), expected_status)

                self.assertIn(expected_message, output.getvalue().lower())
                self.assertNotIn("export", output.getvalue().lower())
                for credential in (*NEW_CREDENTIALS.values(), "fixture-app-key"):
                    self.assertNotIn(credential, output.getvalue())
                opener.assert_called_once()

    def test_write_cache_failure_before_publish_preserves_original_generation(self):
        original_generation = self.create_generation(
            "original", ORIGINAL_CREDENTIALS, publish=True
        )
        _, pending_path = self.cache_state_paths()
        real_replace = self.module.os.replace
        publish_attempted = False

        def fail_publish(source, destination):
            nonlocal publish_attempted
            if (
                pathlib.Path(source) == pending_path
                and pathlib.Path(destination) == self.cache_dir
            ):
                publish_attempted = True
                raise OSError("simulated publish failure")
            return real_replace(source, destination)

        with patch.object(self.module.os, "replace", side_effect=fail_publish):
            with self.assertRaises(self.module.RefreshError):
                self.module.write_cache(self.cache_dir, NEW_CREDENTIALS)

        self.assertTrue(publish_attempted)
        self.assert_usable_cache(ORIGINAL_CREDENTIALS)
        self.assertEqual(
            self.cache_dir.parent / os.readlink(self.cache_dir), original_generation
        )
        self.assertFalse(pending_path.is_symlink())

    def test_main_held_cache_lock_returns_nonzero_without_mutation(self):
        self.settings(
            "cloudtamer.example.test",
            "fixture-app-key",
            "123456789012",
            "fixture-alias",
            "fixture-car",
            load=False,
        )
        original_generation = self.create_generation(
            "original", ORIGINAL_CREDENTIALS, publish=True
        )
        stale_generation = self.create_generation("stale", NEWER_CREDENTIALS)
        lock_path = self.cache_lock_path()
        descriptor = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        output = io.StringIO()

        try:
            with (
                patch.object(
                    self.module.pathlib.Path,
                    "home",
                    return_value=self.home_dir,
                ),
                patch.object(
                    self.module,
                    "request_credentials",
                    return_value=NEW_CREDENTIALS,
                ),
                contextlib.redirect_stdout(output),
                contextlib.redirect_stderr(output),
            ):
                status = self.module.main()
        finally:
            fcntl.flock(descriptor, fcntl.LOCK_UN)
            os.close(descriptor)

        self.assertNotEqual(status, 0)
        self.assertIn("failed", output.getvalue().lower())
        for fixture_value in (
            *ORIGINAL_CREDENTIALS.values(),
            *NEW_CREDENTIALS.values(),
            *NEWER_CREDENTIALS.values(),
            "fixture-app-key",
        ):
            self.assertNotIn(fixture_value, output.getvalue())
        self.assertEqual(
            self.cache_dir.parent / os.readlink(self.cache_dir), original_generation
        )
        self.assert_usable_cache(ORIGINAL_CREDENTIALS)
        self.assertTrue(stale_generation.is_dir())
        legacy_path, pending_path = self.cache_state_paths()
        self.assertFalse(legacy_path.exists())
        self.assertFalse(pending_path.is_symlink())

    def test_write_cache_cleanup_reads_canonical_target_under_lock(self):
        self.create_generation("original", ORIGINAL_CREDENTIALS, publish=True)
        self.create_generation("stale", NEWER_CREDENTIALS)
        real_cleanup = self.module._cleanup_stale_state
        real_readlink = self.module.os.readlink
        cleanup_lock_states = []

        def observe_readlink(path):
            if pathlib.Path(path) == self.cache_dir:
                descriptor = os.open(
                    self.cache_lock_path(), os.O_RDWR | os.O_CREAT, 0o600
                )
                try:
                    try:
                        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    except BlockingIOError:
                        cleanup_lock_states.append(True)
                    else:
                        cleanup_lock_states.append(False)
                        fcntl.flock(descriptor, fcntl.LOCK_UN)
                finally:
                    os.close(descriptor)
            return real_readlink(path)

        def observe_cleanup(cache_dir):
            with patch.object(self.module.os, "readlink", side_effect=observe_readlink):
                return real_cleanup(cache_dir)

        with patch.object(
            self.module, "_cleanup_stale_state", side_effect=observe_cleanup
        ):
            self.module.write_cache(self.cache_dir, NEW_CREDENTIALS)

        self.assertGreaterEqual(len(cleanup_lock_states), 2)
        self.assertTrue(all(cleanup_lock_states))
        self.assert_private_generation(NEW_CREDENTIALS)

    def test_write_cache_recovers_failed_legacy_migration(self):
        self.create_physical_cache(self.cache_dir, ORIGINAL_CREDENTIALS)
        legacy_path, pending_path = self.cache_state_paths()
        real_replace = self.module.os.replace

        def fail_publish_and_rollback(source, destination):
            source = pathlib.Path(source)
            destination = pathlib.Path(destination)
            if source == pending_path and destination == self.cache_dir:
                raise OSError("simulated publish failure")
            if source == legacy_path and destination == self.cache_dir:
                raise OSError("simulated rollback failure")
            return real_replace(source, destination)

        with patch.object(
            self.module.os, "replace", side_effect=fail_publish_and_rollback
        ):
            with self.assertRaises(self.module.RefreshError):
                self.module.write_cache(self.cache_dir, NEW_CREDENTIALS)

        self.assertFalse(self.cache_dir.exists())
        self.assertTrue(legacy_path.is_dir())
        self.assertTrue(pending_path.is_symlink())
        self.assert_usable_cache(NEW_CREDENTIALS, pending_path)

        self.module.write_cache(self.cache_dir, NEW_CREDENTIALS)

        self.assert_private_generation(NEW_CREDENTIALS)
        self.assertFalse(legacy_path.exists())
        self.assertFalse(pending_path.is_symlink())

    def test_write_cache_recovers_stale_transaction_before_new_write_fails(self):
        legacy_path, pending_path = self.cache_state_paths()
        self.create_physical_cache(legacy_path, ORIGINAL_CREDENTIALS)
        incomplete_generation = self.create_generation(
            "incomplete", NEW_CREDENTIALS, complete=False
        )
        os.symlink(incomplete_generation.name, pending_path)

        with patch.object(
            self.module.tempfile,
            "mkdtemp",
            side_effect=OSError("simulated generation creation failure"),
        ):
            with self.assertRaises(self.module.RefreshError):
                self.module.write_cache(self.cache_dir, NEW_CREDENTIALS)

        self.assert_usable_cache(ORIGINAL_CREDENTIALS)
        self.assertFalse(legacy_path.exists())
        self.assertFalse(pending_path.is_symlink())
        self.assertFalse(incomplete_generation.exists())

    def test_write_cache_write_and_chmod_errors_preserve_original_generation(self):
        for failure in ("write", "chmod"):
            with self.subTest(failure=failure):
                cache_dir = self.home_dir / ".cache" / f"kion-aws-cache-{failure}"
                self.cache_dir = cache_dir
                self.create_generation("original", ORIGINAL_CREDENTIALS, publish=True)
                real_chmod = self.module.os.chmod

                def fail_file_chmod(path, mode):
                    if pathlib.Path(path).name == "AWS_SECRET_ACCESS_KEY":
                        raise OSError("simulated credential chmod failure")
                    return real_chmod(path, mode)

                patcher = (
                    patch.object(
                        self.module.os,
                        "fdopen",
                        side_effect=lambda descriptor, *args, **kwargs: FailingWriter(
                            descriptor
                        ),
                    )
                    if failure == "write"
                    else patch.object(
                        self.module.os, "chmod", side_effect=fail_file_chmod
                    )
                )
                with patcher:
                    with self.assertRaises(self.module.RefreshError):
                        self.module.write_cache(cache_dir, NEW_CREDENTIALS)

                self.assert_usable_cache(ORIGINAL_CREDENTIALS, cache_dir)
                _, pending_path = self.cache_state_paths(cache_dir)
                self.assertFalse(pending_path.is_symlink())

    def test_write_cache_cleanup_error_keeps_new_generation_and_retries_later(self):
        original_generation = self.create_generation(
            "original", ORIGINAL_CREDENTIALS, publish=True
        )
        real_rmtree = self.module.shutil.rmtree

        def fail_original_cleanup(path):
            if pathlib.Path(path) == original_generation:
                raise OSError("simulated stale generation cleanup failure")
            return real_rmtree(path)

        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            with patch.object(
                self.module.shutil, "rmtree", side_effect=fail_original_cleanup
            ):
                self.module.write_cache(self.cache_dir, NEW_CREDENTIALS)

        self.assert_private_generation(NEW_CREDENTIALS)
        self.assertTrue(original_generation.exists())
        self.assertIn("cleanup", stderr.getvalue().lower())
        for fixture_value in ORIGINAL_CREDENTIALS.values():
            self.assertNotIn(fixture_value, stderr.getvalue())
        for fixture_value in NEW_CREDENTIALS.values():
            self.assertNotIn(fixture_value, stderr.getvalue())

        self.module.write_cache(self.cache_dir, NEWER_CREDENTIALS)

        self.assert_private_generation(NEWER_CREDENTIALS)
        self.assertFalse(original_generation.exists())
        generation_paths = list(
            self.cache_dir.parent.glob(f".{self.cache_dir.name}.generation-*")
        )
        self.assertEqual(len(generation_paths), 1)


if __name__ == "__main__":
    unittest.main()
