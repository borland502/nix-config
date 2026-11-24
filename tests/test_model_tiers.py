"""Floating OpenAI-family tiers: catalog resolution and harness config writes."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[1]
RESOLVER = ROOT / "scripts/resolve-model-tiers.py"

spec = importlib.util.spec_from_file_location("resolve_model_tiers", RESOLVER)
tiers_mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tiers_mod)


def model(slug, visibility="list", upgrade=None):
    return {"slug": slug, "visibility": visibility, "upgrade": upgrade}


CATALOG = {
    "models": [
        model("auto"),
        model("gpt-6.1-terra"),
        model("gpt-7-sol", visibility="hide"),
        model("gpt-6.1-sol"),
        model("gpt-6-astra"),
        model("gpt-6-sol"),
        model("gpt-6.2-luna"),
        model("gpt-6.10-luna"),
        model("gpt-5.6-sol"),
        model("gpt-5.6-terra"),
    ]
}
TIERS = {
    "family": {"high": "sol", "mid": "terra", "low": "luna"},
    "floor": {"high": "gpt-6-sol", "mid": "gpt-6.1-terra", "low": "gpt-6-luna"},
}
RESOLVED = {"high": "gpt-6.1-sol", "mid": "gpt-6.1-terra", "low": "gpt-6.10-luna"}


class Workspace(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = Path(tmp.name)
        self.catalog = self.dir / "models_cache.json"
        self.catalog.write_text(json.dumps(CATALOG))
        self.tiers = self.write_tiers(TIERS)

    def write_tiers(self, tiers, name="tiers.json"):
        path = self.dir / name
        path.write_text(json.dumps(tiers))
        return path

    def cli(self, *args, tiers=None, catalog=None, check=True):
        cmd = [sys.executable, "-I", str(RESOLVER), "--tiers", str(tiers or self.tiers)]
        cmd += ["--catalog", str(catalog or self.catalog), *map(str, args)]
        return subprocess.run(cmd, text=True, capture_output=True, check=check)


class Resolution(Workspace):
    def test_newest_listed_slug_per_family(self):
        self.assertEqual(json.loads(self.cli("resolve").stdout), RESOLVED)

    def test_floor_wins_over_older_catalog(self):
        tiers = dict(TIERS, floor=dict(TIERS["floor"], high="gpt-6.2-sol"))
        out = self.cli("resolve", tiers=self.write_tiers(tiers, "t2.json"))
        self.assertEqual(json.loads(out.stdout)["high"], "gpt-6.2-sol")

    def test_missing_catalog_falls_back_to_floor(self):
        out = self.cli("resolve", catalog=self.dir / "absent.json")
        self.assertEqual(json.loads(out.stdout), TIERS["floor"])

    def test_upgrade_targets_preserve_family_and_newest_version(self):
        for target in ("gpt-5.6-sol", "gpt-6-sol", "gpt-6.2-terra", "gpt-reserve"):
            with self.subTest(target=target):
                catalog = [model("gpt-6.1-sol", upgrade={"model": target}), model(target)]
                self.assertEqual(tiers_mod.resolve(TIERS, catalog)["high"], "gpt-6.1-sol")

    def test_valid_upgrade_chain_retains_latest_family_model(self):
        catalog = [
            model("gpt-6.1-sol", upgrade={"model": "gpt-6.2-sol"}),
            model("gpt-6.2-sol", upgrade="gpt-6.3-sol"),
            model("gpt-6.3-sol", upgrade="gpt-5.6-sol"),
            model("gpt-5.6-sol"),
        ]
        self.assertEqual(tiers_mod.resolve(TIERS, catalog)["high"], "gpt-6.3-sol")

    def test_floor_lag_warning(self):
        out = self.cli("--warn-floor", "resolve")
        self.assertIn("high floor gpt-6-sol is behind gpt-6.1-sol", out.stderr)
        self.assertNotIn("mid floor", out.stderr)


class CodexConfig(Workspace):
    BODY = (
        '# user comment\n'
        'model = "{model}" # picked in /model\n'
        'model_reasoning_effort = "high"\n\n'
        '[tui]\nmodel = "not-top-level"\n'
    )

    def config(self, model_line=None):
        path = self.dir / "config.toml"
        text = self.BODY.format(model=model_line) if model_line else '# user comment\n\n[tui]\nx = 1\n'
        path.write_text(text)
        return path

    def test_absent_model_is_seeded_with_high(self):
        path = self.config()
        self.cli("codex-config", path)
        data = tomllib.loads(path.read_text())
        self.assertEqual(data["model"], "gpt-6.1-sol")
        self.assertEqual(data["tui"], {"x": 1})
        self.assertIn("# user comment", path.read_text())

    def test_older_same_family_slug_floats_forward(self):
        path = self.config("gpt-5.6-sol")
        self.cli("codex-config", path)
        text = path.read_text()
        self.assertEqual(tomllib.loads(text)["model"], "gpt-6.1-sol")
        self.assertIn("# picked in /model", text)
        self.assertEqual(tomllib.loads(text)["tui"]["model"], "not-top-level")

    def test_current_or_unversioned_choice_is_left_alone(self):
        for slug in ("gpt-6-astra", "gpt-6.1-sol", "auto", "gpt-reserve"):
            path = self.config(slug)
            before = path.read_bytes()
            self.cli("codex-config", path)
            self.assertEqual(path.read_bytes(), before, slug)

    def test_symlinked_config_is_refused(self):
        real = self.config("gpt-5.6-sol")
        link = self.dir / "link.toml"
        link.symlink_to(real)
        self.assertNotEqual(self.cli("codex-config", link, check=False).returncode, 0)
        self.assertIn("gpt-5.6-sol", real.read_text())


class CodexProfiles(Workspace):
    def test_profiles_written_and_unmanaged_kept(self):
        (self.dir / "low.config.toml").write_text('model = "mine"\n')
        self.cli("codex-profiles", self.dir)
        mid = tomllib.loads((self.dir / "mid.config.toml").read_text())
        self.assertEqual(mid, {"model": "gpt-6.1-terra", "model_reasoning_effort": "medium"})
        self.assertEqual((self.dir / "low.config.toml").read_text(), 'model = "mine"\n')
        before = (self.dir / "mid.config.toml").stat().st_mtime_ns
        self.cli("codex-profiles", self.dir)
        self.assertEqual((self.dir / "mid.config.toml").stat().st_mtime_ns, before)


class CodexAgents(Workspace):
    def test_agents_resolved_copied_and_pruned(self):
        tiers = self.write_tiers(dict(TIERS, floor=dict(TIERS["floor"], mid="gpt-5.6-terra")), "t3.json")
        src, dest = self.dir / "src", self.dir / "dest"
        src.mkdir()
        dest.mkdir()
        (src / "a.toml").write_text('name = "a"\nmodel = "gpt-5.6-terra"\ndeveloper_instructions = "model = \\"x\\"\\n"\n')
        (src / "b.toml").write_text('name = "b"\n')
        (dest / "a.toml").symlink_to(src / "a.toml")
        (dest / "c.toml").write_text('name = "c"\n')
        (dest / "user.toml").write_text('name = "user"\n')
        (dest / ".nix-config-managed").write_text("a.toml\nc.toml\n")
        self.cli("codex-agents", src, dest, tiers=tiers)
        a = dest / "a.toml"
        self.assertFalse(a.is_symlink())
        self.assertEqual(tomllib.loads(a.read_text())["model"], "gpt-6.1-terra")
        self.assertEqual(tomllib.loads(a.read_text())["developer_instructions"], 'model = "x"\n')
        self.assertTrue((dest / "b.toml").is_file())
        self.assertFalse((dest / "c.toml").exists())
        self.assertTrue((dest / "user.toml").exists())
        self.assertEqual((dest / ".nix-config-managed").read_text().split(), ["a.toml", "b.toml"])
        self.assertEqual(oct(a.stat().st_mode & 0o777), "0o644")


class CopilotSettings(Workspace):
    def test_high_tier_set_and_other_keys_kept(self):
        path = self.dir / "settings.json"
        path.write_text(json.dumps({"model": "gpt-5.6-terra", "allowedUrls": ["https://github.com"]}))
        self.cli("copilot-settings", path)
        self.assertEqual(json.loads(path.read_text()), {"model": "gpt-6.1-sol", "allowedUrls": ["https://github.com"]})
        self.assertEqual(oct(path.stat().st_mode & 0o777), "0o600")

    def test_missing_settings_created(self):
        path = self.dir / "new/settings.json"
        self.cli("copilot-settings", path, catalog=self.dir / "absent.json")
        self.assertEqual(json.loads(path.read_text()), {"model": "gpt-6-sol"})


if __name__ == "__main__":
    unittest.main()
