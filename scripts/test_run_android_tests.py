#!/usr/bin/env python3
"""Offline checks for the isolated Android instrumentation runner."""

from __future__ import annotations

import contextlib
import importlib.util
from io import StringIO
from pathlib import Path
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().with_name("run_android_tests.py")
SPEC = importlib.util.spec_from_file_location("run_android_tests", SCRIPT)
assert SPEC and SPEC.loader
runner = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = runner
SPEC.loader.exec_module(runner)


class AndroidTestRunnerTests(unittest.TestCase):
    def test_repository_manifest_covers_all_instrumentation_classes(self) -> None:
        batches = runner.verify_batch_manifest(runner.default_android_test_dir())
        self.assertEqual(3, len(batches))
        self.assertEqual(21, sum(len(classes) for classes in batches.values()))
        self.assertIn("AssignmentNotificationPublisherTest", batches[
            "batch1_channel_and_fresh_install"
        ])

    def test_manifest_rejects_unregistered_and_duplicate_classes(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            directory = Path(raw)
            (directory / "AlphaTest.kt").write_text("class AlphaTest", encoding="utf-8")
            batches = runner.verify_batch_manifest(
                directory,
                {"batch": ("AlphaTest",)},
            )
            self.assertEqual(("AlphaTest",), batches["batch"])

            (directory / "BetaTest.kt").write_text("class BetaTest", encoding="utf-8")
            with self.assertRaises(runner.ManifestError):
                runner.verify_batch_manifest(directory, {"batch": ("AlphaTest",)})

            with self.assertRaises(runner.ManifestError):
                runner.verify_batch_manifest(
                    directory,
                    {"one": ("AlphaTest",), "two": ("AlphaTest",)},
                )

    def test_protected_serial_is_rejected_before_any_command(self) -> None:
        stdout = StringIO()
        stderr = StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = runner.main(
                [
                    "--serial",
                    "127.0.0.1:16448",
                    "--dry-run",
                    "--skip-build",
                ]
            )
        self.assertEqual(2, code)
        self.assertIn("Refusing protected", stderr.getvalue())
        self.assertNotIn("am instrument", stdout.getvalue())

    def test_dry_run_lists_isolated_batches_in_order(self) -> None:
        stdout = StringIO()
        with contextlib.redirect_stdout(stdout):
            code = runner.main(
                [
                    "--serial",
                    "127.0.0.1:16384",
                    "--adb",
                    "adb",
                    "--dry-run",
                    "--skip-build",
                ]
            )
        text = stdout.getvalue()
        self.assertEqual(0, code)
        first = text.index("[DRY-RUN] batch1_channel_and_fresh_install")
        second = text.index("[DRY-RUN] batch2_reminder_and_background")
        third = text.index("[DRY-RUN] batch3_widget_and_boundaries")
        self.assertLess(first, second)
        self.assertLess(second, third)
        self.assertEqual(5 * 3, text.count("adb -s 127.0.0.1:16384"))
        self.assertIn("uninstall com.example.studyassistant.journal", text)
        self.assertIn("uninstall com.example.studyassistant.journal.test", text)
        self.assertIn("install -r", text)
        self.assertIn("am instrument -w -r", text)

    def test_parser_counts_pass_fail_and_assumption_skip(self) -> None:
        output = "\n".join(
            [
                "INSTRUMENTATION_STATUS: class=com.example.OneTest",
                "INSTRUMENTATION_STATUS: test=passes",
                "INSTRUMENTATION_STATUS_CODE: 1",
                "INSTRUMENTATION_STATUS_CODE: 0",
                "INSTRUMENTATION_STATUS: class=com.example.OneTest",
                "INSTRUMENTATION_STATUS: test=fails",
                "INSTRUMENTATION_STATUS_CODE: -2",
                "INSTRUMENTATION_STATUS: class=com.example.OneTest",
                "INSTRUMENTATION_STATUS: test=skips",
                "INSTRUMENTATION_STATUS_CODE: -4",
            ]
        )
        summary = runner.summarize_results("batch", output, 1)
        self.assertEqual(1, summary.passed)
        self.assertEqual(1, summary.failed)
        self.assertEqual(1, summary.skipped)
        self.assertEqual(1, summary.assumption_skipped)
        self.assertIsNone(summary.execution_error)

        fallback = runner.summarize_results(
            "batch",
            "OK (7 tests)",
            0,
        )
        self.assertEqual(7, fallback.passed)


if __name__ == "__main__":
    unittest.main()
