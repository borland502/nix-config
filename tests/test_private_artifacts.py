import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock
from contextlib import contextmanager

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "chezmoi/dot_local/lib"))
from agent_tools import artifacts  # noqa: E402


class PrivateArtifactsTests(unittest.TestCase):
    def test_private_directory_mode_and_symlink_rejection(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp) / "parent/private"
            self.assertTrue(hasattr(artifacts, "private_directory"))
            artifacts.private_directory(directory)
            directory.chmod(0o755)
            artifacts.private_directory(directory)
            self.assertEqual(directory.stat().st_mode & 0o777, 0o700)
            link = Path(tmp) / "link"
            link.symlink_to(directory, target_is_directory=True)
            with self.assertRaises(OSError):
                artifacts.private_directory(link)

    def test_failed_atomic_write_preserves_target_and_cleans_temporary(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "settings"
            target.write_bytes(b"original")
            with self.assertRaises(RuntimeError):
                with artifacts.atomic_output(target, replace=True) as output:
                    output.write(b"partial")
                    raise RuntimeError("write failed")
            self.assertEqual(target.read_bytes(), b"original")
            self.assertEqual(list(Path(tmp).iterdir()), [target])

    def test_merger_preserves_edit_during_final_fsync(self):
        spec = importlib.util.spec_from_file_location("capture_merger_fsync", ROOT / "scripts/merge-agent-capture-hooks.py")
        merger = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(merger)
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "settings.json"
            source = Path(tmp) / "hooks.json"
            target.write_bytes(b"{}")
            source.write_text('{"hooks": {}}')
            original_fsync = artifacts.os.fsync

            def concurrent_fsync(fd):
                original_fsync(fd)
                target.write_bytes(b"concurrent edit")

            with mock.patch.object(artifacts.os, "fsync", concurrent_fsync), mock.patch.object(sys, "argv", ["merger", str(target), str(source)]):
                with self.assertRaisesRegex(ValueError, "settings changed"):
                    merger.main()
            self.assertEqual(target.read_bytes(), b"concurrent edit")
            self.assertEqual(set(Path(tmp).iterdir()), {target, source})

    def test_merger_detects_concurrent_edit_before_publication(self):
        spec = importlib.util.spec_from_file_location("capture_merger", ROOT / "scripts/merge-agent-capture-hooks.py")
        merger = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(merger)
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "settings.json"
            source = Path(tmp) / "hooks.json"
            target.write_bytes(b"{}")
            source.write_text('{"hooks": {}}')

            @contextmanager
            def concurrent_edit(path, *, replace, before_publish):
                with artifacts.atomic_output(path, replace=replace, before_publish=before_publish) as output:
                    target.write_bytes(b"concurrent edit")
                    yield output

            with mock.patch.object(merger, "atomic_output", concurrent_edit, create=True), mock.patch.object(sys, "argv", ["merger", str(target), str(source)]):
                with self.assertRaisesRegex(ValueError, "settings changed"):
                    merger.main()
            self.assertEqual(target.read_bytes(), b"concurrent edit")
            self.assertEqual(set(Path(tmp).iterdir()), {target, source})
