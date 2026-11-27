#!/usr/bin/env python3
"""Unit tests for scripts/verify_local_gate.py."""

from __future__ import annotations

import contextlib
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPTS_DIR = Path(__file__).resolve().parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import verify_local_gate as mod  # noqa: E402


class VerifyLocalGateTests(unittest.TestCase):
    def test_format_uses_origin_merge_base_even_when_last_commit_is_docs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            app = repo / "app"
            app.mkdir()

            def git(*args: str) -> bytes:
                return subprocess.check_output(["git", "-c", "commit.gpgsign=false", *args], cwd=repo)

            git("init", "-b", "main", "--template=")
            git("config", "user.email", "test@example.com")
            git("config", "user.name", "Test")
            git("commit", "--allow-empty", "-m", "old local main")
            (app / "already_integrated.dart").write_text("void main() {}\n", encoding="utf-8")
            git("add", "app")
            git("commit", "-m", "integrated in remote main")
            git("update-ref", "refs/remotes/origin/main", "HEAD")
            git("switch", "-c", "dev")
            git("branch", "-f", "main", "HEAD^")
            (app / "earlier.dart").write_text("void main() {}\n", encoding="utf-8")
            git("add", "app")
            git("commit", "-m", "Dart change")
            (repo / "state.md").write_text("development state", encoding="utf-8")
            git("add", "state.md")
            git("commit", "-m", "docs")

            self.assertEqual(mod._changed_dart_files(repo, app), ["earlier.dart"])
            self.assertEqual(mod._changed_dart_files(repo, app, "HEAD^"), [])
            with self.assertRaisesRegex(RuntimeError, "Invalid Dart format baseline"):
                mod._changed_dart_files(repo, app, "nonexistent")

    def test_changed_dart_files_includes_untracked_new_dart_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            app_dir = repo / "study_assistant-1.1.0" / "local_app"
            (app_dir / "lib").mkdir(parents=True, exist_ok=True)
            (app_dir / "test").mkdir(parents=True, exist_ok=True)
            subprocess.run(["git", "init"], cwd=repo, check=True, capture_output=True)
            subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=repo, check=True)
            subprocess.run(["git", "config", "user.name", "Test"], cwd=repo, check=True)

            (app_dir / "lib" / "main.dart").write_text("void main() {}\n", encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-m", "init"], cwd=repo, check=True, capture_output=True)

            # Create a brand-new untracked Dart test file.
            (app_dir / "test" / "new_case_test.dart").write_text("void main() {}\n", encoding="utf-8")
            changed = mod._changed_dart_files(repo, app_dir)
            self.assertIn("test/new_case_test.dart", changed)

    def test_quick_mode_without_tests_or_skip_flag_is_rejected(self) -> None:
        # Passing neither --tests nor --skip-flutter-tests in default quick mode
        # must fail fast rather than silently skipping tests and printing [PASS].
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            exit_code = mod.main([])
        self.assertEqual(exit_code, 2)
        self.assertIn("--tests", stderr.getvalue())
        self.assertIn("--skip-flutter-tests", stderr.getvalue())

    def test_allow_dev_metadata_on_dev_branch_without_dev_suffix(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            subprocess.run(["git", "init", "-b", "dev"], cwd=repo, check=True, capture_output=True)
            subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=repo, check=True)
            subprocess.run(["git", "config", "user.name", "Test"], cwd=repo, check=True)
            (repo / "README.md").write_text("hi\n", encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-m", "init"], cwd=repo, check=True, capture_output=True)

            self.assertTrue(mod._should_allow_dev_metadata(repo, release_flag=False))
            self.assertFalse(mod._should_allow_dev_metadata(repo, release_flag=True))

            subprocess.run(["git", "checkout", "-b", "main"], cwd=repo, check=True, capture_output=True)
            self.assertTrue(mod._should_allow_dev_metadata(repo, release_flag=False))
            self.assertFalse(mod._should_allow_dev_metadata(repo, release_flag=True))

    def test_build_flutter_test_cmd_applies_default_and_custom_timeouts(self) -> None:
        default_cmd = mod._build_flutter_test_cmd("flutter", ["test/a_test.dart"])
        self.assertEqual(
            [
                "flutter",
                "--no-version-check",
                "test",
                "--no-pub",
                "--timeout",
                mod.DEFAULT_TEST_CASE_TIMEOUT,
                "test/a_test.dart",
            ],
            default_cmd,
        )
        # Flutter test defaults to 30s when --timeout is omitted, so 'none' must be
        # forwarded explicitly to disable per-test timeouts.
        disabled_cmd = mod._build_flutter_test_cmd(
            "flutter",
            ["test/a_test.dart"],
            test_case_timeout="NONE",
        )
        self.assertEqual(
            [
                "flutter",
                "--no-version-check",
                "test",
                "--no-pub",
                "--timeout",
                "none",
                "test/a_test.dart",
            ],
            disabled_cmd,
        )
        omitted_cmd = mod._build_flutter_test_cmd(
            "flutter",
            ["test/a_test.dart"],
            test_case_timeout="",
        )
        self.assertNotIn("--timeout", omitted_cmd)
        self.assertEqual(
            ["flutter", "--no-version-check", "test", "--no-pub", "test/a_test.dart"],
            omitted_cmd,
        )

    def test_run_flutter_step_kills_hung_process_and_reports_last_test_line(self) -> None:
        # Emit bare '\r' without trailing '\n' (plus HH:MM:SS prefix and ANSI codes) to prove
        # chunked decoding records the active progress frame immediately without blocking on '\n'.
        hung_script = (
            "import sys, time\n"
            "sys.stdout.write('\\x1b[32m00:01 +0: loading test/fake_hang_test.dart\\x1b[0m\\r"
            "\\x1b[33m01:02:03 +1950: fakeAsync bare-cr hung case\\x1b[0m\\r')\n"
            "sys.stdout.flush()\n"
            "time.sleep(30)\n"
        )
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            with self.assertRaises(RuntimeError) as raised:
                mod._run_flutter_step(
                    "Targeted Flutter tests (1 files)",
                    [sys.executable, "-c", hung_script],
                    Path(__file__).resolve().parent,
                    timeout_seconds=1,
                )
        message = str(raised.exception)
        self.assertIn("timed out after 1s", message)
        self.assertIn("01:02:03 +1950: fakeAsync bare-cr hung case", message)
        self.assertNotIn("\x1b[", message)


if __name__ == "__main__":
    unittest.main()
