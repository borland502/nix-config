import importlib.machinery
import importlib.util
import json
import pathlib
import tempfile
import unittest
from unittest.mock import Mock, patch


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT_PATH = (
    REPOSITORY_ROOT / "chezmoi" / "dot_local" / "bin" / "executable_kion-aws-refresh"
)


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
                    "data": {
                        "access_key": "fixture-access",
                        "secret_access_key": "fixture-secret",
                        "session_token": "fixture-token",
                    },
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
        self.assertEqual(
            json.loads(request.data),
            {
                "account_number": "123456789012",
                "account_alias": "",
                "cloud_access_role_name": "fixture-car",
            },
        )
        self.assertEqual(request.get_header("Authorization"), "Bearer fixture-app-key")
        self.assertEqual(self.cache_dir.stat().st_mode & 0o777, 0o700)
        for filename in self.module.CACHE_FILES.values():
            self.assertEqual((self.cache_dir / filename).stat().st_mode & 0o777, 0o600)

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
                    "data": {
                        "access_key": "fixture-access",
                        "secret_access_key": "fixture-secret",
                        "session_token": "fixture-token",
                    },
                },
            ),
            FakeResponse(201, {"status": 201, "data": {"access_key": "fixture-access"}}),
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

    def test_write_cache_preserves_existing_cache_when_replacement_fails(self):
        original = {
            "AWS_ACCESS_KEY_ID": b"old-access",
            "AWS_SECRET_ACCESS_KEY": b"old-secret",
            "AWS_SESSION_TOKEN": b"old-token",
        }
        self.cache_dir.mkdir(parents=True)
        for filename, contents in original.items():
            (self.cache_dir / filename).write_bytes(contents)

        real_replace = self.module.os.replace
        replacement_attempts = 0

        def fail_new_cache_replacement(source, destination):
            nonlocal replacement_attempts
            if pathlib.Path(destination) == self.cache_dir:
                replacement_attempts += 1
                if replacement_attempts == 1:
                    raise OSError("simulated replacement failure")
            return real_replace(source, destination)

        with patch.object(self.module.os, "replace", side_effect=fail_new_cache_replacement):
            with self.assertRaises(self.module.RefreshError):
                self.module.write_cache(
                    self.cache_dir,
                    {
                        "access_key": "fixture-access",
                        "secret_access_key": "fixture-secret",
                        "session_token": "fixture-token",
                    },
                )

        self.assertEqual(
            {filename: (self.cache_dir / filename).read_bytes() for filename in original},
            original,
        )


if __name__ == "__main__":
    unittest.main()
