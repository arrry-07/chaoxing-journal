#!/usr/bin/env python3
"""Offline checks for the isolated Android instrumentation runner."""

from __future__ import annotations

import contextlib
import importlib.util
from io import StringIO
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(__file__).resolve().with_name("run_android_tests.py")
SPEC = importlib.util.spec_from_file_location("run_android_tests", SCRIPT)
assert SPEC and SPEC.loader
runner = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = runner
SPEC.loader.exec_module(runner)


class AndroidTestRunnerTests(unittest.TestCase):
    def test_repository_manifest_covers_all_instrumentation_classes(self) -> None:
        batches = runner.verify_batch_manifest(runner.default_android_test_dir())
        self.assertEqual(4, len(batches))
        self.assertEqual(22, sum(len(classes) for classes in batches.values()))
        self.assertIn("AssignmentNotificationPublisherTest", batches[
            "batch1_channel_and_fresh_install"
        ])
        self.assertEqual(
            ("ReminderApiMatrixTest",),
            batches["batch4_api_matrix_and_doze"],
        )

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
        fourth = text.index("[DRY-RUN] batch4_api_matrix_and_doze")
        self.assertLess(first, second)
        self.assertLess(second, third)
        self.assertLess(third, fourth)
        self.assertEqual(5 * 4, text.count("adb -s 127.0.0.1:16384"))
        self.assertIn("uninstall com.example.studyassistant.journal", text)
        self.assertIn("uninstall com.example.studyassistant.journal.test", text)
        self.assertIn("install -r", text)
        self.assertIn("am instrument -w -r", text)

    def test_dry_run_uses_fully_qualified_class_names(self) -> None:
        stdout = StringIO()
        with contextlib.redirect_stdout(stdout):
            code = runner.main(
                [
                    "--serial",
                    "127.0.0.1:16384",
                    "--dry-run",
                    "--skip-build",
                ]
            )
        text = stdout.getvalue()
        self.assertEqual(0, code)
        self.assertIn(
            "-e class com.example.studyassistant.AssignmentNotificationPublisherTest",
            text,
        )
        self.assertIn(
            "com.example.studyassistant.RealAccountHeadlessEntryTest",
            text,
        )
        self.assertNotIn("-e class AssignmentNotificationPublisherTest", text)

    def test_gradle_build_runs_inside_the_android_project(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            build_root = Path(raw) / "local_app"
            build_root.mkdir()
            calls: list[dict[str, object]] = []

            def fake_run(cmd, cwd=None, check=False):  # noqa: ANN001
                calls.append({"cmd": cmd, "cwd": cwd})
                return subprocess.CompletedProcess(cmd, 0, "OK (1 test)", "")

            def fake_find(app_root: Path, name: str) -> Path:
                return app_root / name

            with (
                mock.patch.object(runner, "_build_root", return_value=build_root),
                mock.patch.object(runner, "_run", side_effect=fake_run),
                mock.patch.object(runner, "_find_apk", side_effect=fake_find),
                contextlib.redirect_stdout(StringIO()),
            ):
                code = runner.main(["--serial", "emulator-1"])
            self.assertEqual(0, code)
            gradle_calls = [
                call for call in calls if "gradlew" in " ".join(map(str, call["cmd"]))
            ]
            self.assertEqual(1, len(gradle_calls))
            self.assertEqual(build_root / "android", gradle_calls[0]["cwd"])

    def test_run_decodes_output_as_utf8_with_replacement(self) -> None:
        seen: dict[str, object] = {}

        def fake_run(cmd, **kwargs):  # noqa: ANN001
            seen["cmd"] = cmd
            seen.update(kwargs)
            return subprocess.CompletedProcess(cmd, 0, "OK (1 test)", "")

        with (
            mock.patch.object(runner.subprocess, "run", side_effect=fake_run),
            contextlib.redirect_stdout(StringIO()),
        ):
            runner._run(["adb", "shell", "am", "instrument"])

        self.assertTrue(seen["text"])
        self.assertEqual("utf-8", seen["encoding"])
        self.assertEqual("replace", seen["errors"])

    def test_skip_build_with_work_dir_reuses_the_ascii_mirror(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            work_dir = Path(raw)
            seen: list[Path] = []

            def fake_find(app_root: Path, name: str) -> Path:
                seen.append(app_root)
                return app_root / name

            with (
                mock.patch.object(runner, "_find_apk", side_effect=fake_find),
                mock.patch.object(
                    runner,
                    "_run",
                    return_value=subprocess.CompletedProcess(
                        [], 0, "OK (1 test)", ""
                    ),
                ),
                contextlib.redirect_stdout(StringIO()),
            ):
                code = runner.main(
                    [
                        "--serial",
                        "emulator-1",
                        "--skip-build",
                        "--work-dir",
                        str(work_dir),
                    ]
                )
            self.assertEqual(0, code)
            self.assertTrue(seen)
            self.assertEqual(work_dir / "local_app", seen[0])

    def test_crashed_or_empty_runs_are_execution_errors(self) -> None:
        crashed = runner.summarize_results(
            "batch",
            "INSTRUMENTATION_STATUS: Error=Process crashed",
            0,
        )
        self.assertIsNotNone(crashed.execution_error)

        class_not_found = runner.summarize_results(
            "batch",
            "INSTRUMENTATION_STATUS: shortMsg=ClassNotFoundException",
            0,
        )
        self.assertIsNotNone(class_not_found.execution_error)

        for marker in (
            "INSTRUMENTATION_RESULT: shortMsg=Runner stopped unexpectedly.",
            "INSTRUMENTATION_FAILED: com.example.OneTest#passes",
        ):
            with self.subTest(marker=marker):
                summary = runner.summarize_results(
                    "batch", f"OK (1 test)\n{marker}", 0
                )
                self.assertEqual(1, summary.passed)
                self.assertEqual(marker, summary.execution_error)

        unfinished = runner.summarize_results(
            "batch",
            "\n".join(
                [
                    "INSTRUMENTATION_STATUS: class=com.example.OneTest",
                    "INSTRUMENTATION_STATUS: test=passes",
                    "INSTRUMENTATION_STATUS_CODE: 1",
                ]
            ),
            0,
        )
        self.assertIn("did not finish", unfinished.execution_error or "")

        failed_to_start = "INSTRUMENTATION_FAILED: Unable to find instrumentation"
        self.assertEqual(
            failed_to_start,
            runner.summarize_results("batch", failed_to_start, 0).execution_error,
        )

        empty = runner.summarize_results("batch", "", 0)
        self.assertEqual(
            "instrumentation reported no test results", empty.execution_error
        )

        ok = runner.summarize_results("batch", "OK (7 tests)", 0)
        self.assertEqual(7, ok.passed)
        self.assertIsNone(ok.execution_error)

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

    def test_protected_first_install_time_is_rejected_even_with_allow_wipe_physical(
        self,
    ) -> None:
        info = runner.DeviceInfo(
            serial="127.0.0.1:9999",
            sdk_int=35,
            abi="x86_64",
            manufacturer="Google",
            model="sdk_gphone",
            timezone="Asia/Shanghai",
            is_emulator=True,
            installed_version="1.8.28",
            installed_code="122",
            first_install_time="2026-11-04 19:05:10",
        )
        refusal = runner.validate_destructive_target(
            info,
            allow_wipe_physical=True,
        )
        self.assertIsNotNone(refusal)
        self.assertIn("firstInstallTime", refusal)

    def test_physical_device_rejected_without_allow_wipe_physical(self) -> None:
        info = runner.DeviceInfo(
            serial="ABC123",
            sdk_int=35,
            abi="arm64-v8a",
            manufacturer="Huawei",
            model="Phone",
            timezone="Asia/Shanghai",
            is_emulator=False,
            installed_version="1.8.28",
            installed_code="122",
            first_install_time="2026-11-01 10:00:00",
        )
        self.assertIsNotNone(
            runner.validate_destructive_target(
                info,
                allow_wipe_physical=False,
            )
        )
        self.assertIsNone(
            runner.validate_destructive_target(
                info,
                allow_wipe_physical=True,
            )
        )

    def test_multi_serial_matrix_builds_once_and_runs_each_target(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            build_root = Path(raw) / "local_app"
            build_root.mkdir()
            calls: list[list[str]] = []

            def fake_run(cmd, cwd=None, check=False):  # noqa: ANN001
                calls.append([str(part) for part in cmd])
                return subprocess.CompletedProcess(cmd, 0, "OK (1 test)", "")

            def fake_find(app_root: Path, name: str) -> Path:
                return app_root / name

            with (
                mock.patch.object(runner, "_build_root", return_value=build_root),
                mock.patch.object(runner, "_run", side_effect=fake_run),
                mock.patch.object(runner, "_find_apk", side_effect=fake_find),
                contextlib.redirect_stdout(StringIO()),
            ):
                code = runner.main(
                    [
                        "--serial",
                        "emulator-1",
                        "--serial",
                        "emulator-2",
                    ]
                )
            self.assertEqual(0, code)
            gradle = [
                cmd for cmd in calls if "gradlew" in " ".join(cmd)
            ]
            self.assertEqual(1, len(gradle))
            instruments = [
                cmd for cmd in calls if "am" in cmd and "instrument" in cmd
            ]
            self.assertEqual(8, len(instruments))
            self.assertTrue(any("-s" in cmd and "emulator-1" in cmd for cmd in instruments))
            self.assertTrue(any("-s" in cmd and "emulator-2" in cmd for cmd in instruments))

    def test_mirror_local_properties_repairs_missing_android36_without_touching_repo(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            mirror = root / "mirror"
            sdk = root / "sdk"
            (sdk / "platforms" / "android-36").mkdir(parents=True)
            (mirror / "android").mkdir(parents=True)
            properties = mirror / "android" / "local.properties"
            properties.write_text(
                "sdk.dir=C\\:\\\\missing\\\\sdk\n",
                encoding="utf-8",
            )
            repo_properties = runner.local_app_root() / "android" / "local.properties"
            before = repo_properties.read_text(encoding="utf-8") if repo_properties.is_file() else None
            runner.ensure_mirror_local_properties(
                mirror,
                sdk_dir=sdk,
                flutter_sdk=None,
            )
            repaired = properties.read_text(encoding="utf-8")
            self.assertIn("sdk.dir=", repaired)
            values = runner._read_properties(properties)
            self.assertEqual(str(sdk), values["sdk.dir"])
            after = repo_properties.read_text(encoding="utf-8") if repo_properties.is_file() else None
            self.assertEqual(before, after)

    def test_doze_probe_always_restores_deviceidle_and_battery_on_failure(self) -> None:
        calls: list[list[str]] = []

        def fake_run(cmd, cwd=None, check=False):  # noqa: ANN001
            calls.append([str(part) for part in cmd])
            return subprocess.CompletedProcess(cmd, 0, "deep-idle", "")

        def action() -> None:
            raise RuntimeError("instrumentation failed")

        with mock.patch.object(runner, "_run", side_effect=fake_run):
            with self.assertRaises(RuntimeError):
                runner.run_with_doze("emulator-1", "adb", action)
        flat = [" ".join(cmd) for cmd in calls]
        self.assertTrue(any("deviceidle force-idle" in line for line in flat))
        self.assertTrue(any("deviceidle unforce" in line for line in flat))
        self.assertTrue(any("battery reset" in line for line in flat))

    def test_oem_readonly_audit_executes_zero_destructive_commands(self) -> None:
        calls: list[list[str]] = []

        def fake_run(cmd, cwd=None, check=False):  # noqa: ANN001
            calls.append([str(part) for part in cmd])
            joined = " ".join(str(part) for part in cmd)
            text = ""
            if "getprop" in cmd:
                text = (
                    "[ro.build.version.sdk]: [35]\n"
                    "[ro.product.cpu.abi]: [x86_64]\n"
                    "[ro.kernel.qemu]: [1]\n"
                    "[persist.sys.timezone]: [Asia/Shanghai]\n"
                )
            elif "dumpsys" in cmd and "package" in cmd:
                text = (
                    "versionName=1.8.28\n"
                    "versionCode=122\n"
                    "firstInstallTime=2026-11-04 19:05:10\n"
                )
            elif "appops" in cmd:
                text = "SCHEDULE_EXACT_ALARM: allow"
            elif "deviceidle" in cmd:
                text = "com.example.studyassistant.journal"
            elif "alarm" in joined:
                text = "RTC_WAKEUP com.example.studyassistant.journal ASSIGNMENT_DEADLINE"
            elif "notification" in joined:
                text = "com.example.studyassistant.journal importance=3"
            return subprocess.CompletedProcess(cmd, 0, text, "")

        with mock.patch.object(runner, "_run", side_effect=fake_run):
            code, report = runner.run_oem_readonly_audit(
                "127.0.0.1:16448",
                "adb",
            )
        self.assertEqual(0, code)
        self.assertIn("Exact alarm app-op", report)
        forbidden = (
            "uninstall",
            "install -r",
            "pm clear",
            "pm grant",
            "pm revoke",
            "appops set",
            "am instrument",
            "force-idle",
        )
        for cmd in calls:
            joined = " ".join(cmd)
            for token in forbidden:
                self.assertNotIn(token, joined)

    def test_instrument_command_never_enables_real_account_flag(self) -> None:
        for classes in runner.ANDROID_TEST_BATCHES.values():
            command = runner.instrument_command(
                "emulator-1",
                "adb",
                classes,
            )
            self.assertNotIn("realAccount", " ".join(command))


if __name__ == "__main__":
    unittest.main()
