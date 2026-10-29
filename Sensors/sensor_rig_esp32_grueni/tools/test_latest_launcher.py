"""Exercise launcher routing without building, flashing, or opening a port."""
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch
import run_latest_sensors as launcher


class LauncherTests(unittest.TestCase):
    def test_build_only_compiles_requested_profile_without_capture(self):
        for count in (4, 5):
            with patch("sys.argv", ["run", "--sensors", str(count), "--build-only"]), \
                    patch.object(launcher.importlib.util, "find_spec", return_value=True), \
                    patch.object(launcher.subprocess, "run", return_value=SimpleNamespace(returncode=0)) as run, \
                    patch.object(launcher, "run_logged") as logged:
                self.assertEqual(launcher.main(), 0)
                self.assertIn(f"grueni_latest{count}_500hz", run.call_args.args[0])
                self.assertNotIn("upload", run.call_args.args[0])
                logged.assert_not_called()

    def test_upload_then_check_uses_matching_count_and_strategy(self):
        for count in (4, 5):
            with tempfile.TemporaryDirectory() as directory, \
                    patch("sys.argv", ["run", "--sensors", str(count)]), \
                    patch.object(launcher, "PROJECT", Path(directory)), \
                    patch.object(launcher.importlib.util, "find_spec", return_value=True), \
                    patch.object(launcher, "run_logged", return_value=0) as logged:
                self.assertEqual(launcher.main(), 0)
                build, capture = [call.args[0] for call in logged.call_args_list]
                self.assertIn(f"grueni_latest{count}_500hz", build)
                self.assertEqual(build[-4:], ["-t", "upload", "--upload-port", "COM8"])
                self.assertEqual(capture[capture.index("--sensors") + 1], str(count))
                self.assertEqual(capture[capture.index("--acquisition") + 1], "latest")

    def test_failed_upload_never_starts_capture(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch("sys.argv", ["run", "--sensors", "4"]), \
                patch.object(launcher, "PROJECT", Path(directory)), \
                patch.object(launcher.importlib.util, "find_spec", return_value=True), \
                patch.object(launcher, "run_logged", return_value=1) as logged:
            self.assertEqual(launcher.main(), 1)
            logged.assert_called_once()

    def test_check_only_never_uploads(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch("sys.argv", ["run", "--sensors", "5", "--check-only"]), \
                patch.object(launcher, "PROJECT", Path(directory)), \
                patch.object(launcher.importlib.util, "find_spec", return_value=True), \
                patch.object(launcher, "run_logged", return_value=0) as logged:
            self.assertEqual(launcher.main(), 0)
            logged.assert_called_once()
            self.assertNotIn("upload", logged.call_args.args[0])


if __name__ == "__main__":
    unittest.main()
