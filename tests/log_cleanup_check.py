#!/usr/bin/env python3
"""Deletion checks use only a temporary fake workspace."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from purge_logs import active_paths, expired_logs, purge


class CleanupCheck(unittest.TestCase):
    def test_only_expired_generated_logs_are_removed(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            old = time.time() - 48 * 3600
            names = ["build/dev/old/host.log", "build/dev/old/ai-1.jsonl.2", "build/dev/old/ai-2.json", "replays/match.replay.jsonl",
                     "build/dev/fresh/host.log", "build/dev/active/host.log", "build/dev/pinned/host.log", "build/dev/old/client/fixture.log",
                     "server/authored.log", "build/dev/old/metadata.json", "build/dev/old/host", "logs/export.log"]
            for name in names:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("retained test data")
                if "/fresh/" not in name: os.utime(path, (old, old))
            (root / "build/dev/pinned/.keep-logs").touch()
            outside = root / "outside.log"
            outside.write_text("outside")
            os.utime(outside, (old, old))
            (root / "build/link.log").symlink_to(outside)
            (root / "build/linked-directory").symlink_to(root / "server", target_is_directory=True)
            active = {root / "build/dev/active"}
            dry = purge(root, 24, False, active)
            self.assertEqual(dry["eligible_files"], 5)
            self.assertTrue(all((root / name).exists() for name in names))
            result = purge(root, 24, True, active)
            self.assertEqual(result["removed_files"], 5)
            self.assertEqual(result["errors"], [])
            self.assertTrue(all((root / name).exists() for name in names[4:11]))
            self.assertEqual(outside.read_text(), "outside")
            self.assertTrue((root / "build/link.log").is_symlink())
            self.assertFalse(expired_logs(root, time.time() - 24 * 3600, active))

    def test_retention_must_be_positive(self):
        with self.assertRaises(ValueError): purge(Path("unused"), 0, True, set())

    def test_live_process_protects_its_whole_run(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            run = root / "build/dev/running"
            log = run / "host.log"
            run.mkdir(parents=True)
            log.write_text("old but active")
            old = time.time() - 48 * 3600
            os.utime(log, (old, old))
            process = subprocess.Popen([sys.executable, "-c", "import time; print('ready', flush=True); time.sleep(10)", str(run / "host")], stdout=subprocess.PIPE, text=True)
            try:
                self.assertEqual(process.stdout.readline().strip(), "ready")
                self.assertIn(run, active_paths(root))
                self.assertEqual(purge(root, 24, True)["removed_files"], 0)
                self.assertTrue(log.exists())
            finally:
                process.terminate()
                process.wait(timeout=5)
                process.stdout.close()
            self.assertEqual(purge(root, 24, True)["removed_files"], 1)


if __name__ == "__main__":
    unittest.main()
