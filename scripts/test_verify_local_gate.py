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
            self.assertFalse(mod._should_allow_dev_metadata(repo, release_flag=False))


if __name__ == "__main__":
    unittest.main()
