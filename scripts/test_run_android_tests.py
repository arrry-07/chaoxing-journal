#!/usr/bin/env python3
"""Offline checks for the isolated Android instrumentation runner."""

from __future__ import annotations

import contextlib
import importlib.util
from io import StringIO
import os
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

    def test_doze_probe_reports_real_state_instead_of_assuming_idle(self) -> None:
        readings = iter(["ACTIVE", "ACTIVE"])

        def fake_run(cmd, cwd=None, check=False):  # noqa: ANN001
            if "get" in cmd and "deep" in cmd:
                return subprocess.CompletedProcess(
                    cmd,
                    0,
                    next(readings),
                    "",
                )
            return subprocess.CompletedProcess(cmd, 0, "", "")

        with mock.patch.object(runner, "_run", side_effect=fake_run):
            _, state = runner.run_with_doze(
                "emulator-1",
                "adb",
                lambda: [],
            )
        self.assertIn("unsupported", state)
        self.assertIn("ACTIVE", state)

    def test_doze_probe_recognizes_deep_state_regex_and_idle(self) -> None:
        readings = iter([
            "Light state: ACTIVE, deep state: ACTIVE",
            "Light state: ACTIVE, deep state: IDLE",
        ])

        def fake_run(cmd, cwd=None, check=False):  # noqa: ANN001
            if "get" in cmd and "deep" in cmd:
                return subprocess.CompletedProcess(cmd, 0, next(readings), "")
            return subprocess.CompletedProcess(cmd, 0, "", "")

        with mock.patch.object(runner, "_run", side_effect=fake_run):
            _, state = runner.run_with_doze(
                "emulator-1",
                "adb",
                lambda: [],
            )
        self.assertTrue(state.startswith("IDLE (from ACTIVE)"))

    def test_doze_probe_propagates_manifest_error(self) -> None:
        def fake_run(cmd, cwd=None, check=False):  # noqa: ANN001
            if "force-idle" in " ".join(cmd):
                return subprocess.CompletedProcess(cmd, 1, "", "device offline")
            return subprocess.CompletedProcess(cmd, 0, "ACTIVE", "")

        with mock.patch.object(runner, "_run", side_effect=fake_run):
            with self.assertRaises(runner.ManifestError) as raised:
                runner.run_with_doze("emulator-1", "adb", lambda: [])
        self.assertIn("force-idle", str(raised.exception))

    def test_mirror_explicit_sdk_wins_over_existing_valid_copy(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            mirror = root / "mirror"
            current = root / "current"
            explicit = root / "explicit"
            for sdk in (current, explicit):
                (sdk / "platforms" / "android-36").mkdir(parents=True)
            (mirror / "android").mkdir(parents=True)
            properties = mirror / "android" / "local.properties"
            properties.write_text(
                f"sdk.dir={runner._properties_escape(str(current))}\n",
                encoding="utf-8",
            )
            runner.ensure_mirror_local_properties(
                mirror,
                sdk_dir=explicit,
                flutter_sdk=None,
            )
            values = runner._read_properties(properties)
            self.assertEqual(str(explicit), values["sdk.dir"])

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
                text = (
                    "com.example.studyassistant.journal\n"
                    "mChannelId=deadline importance=4\n"
                )
            return subprocess.CompletedProcess(cmd, 0, text, "")

        with mock.patch.object(runner, "_run", side_effect=fake_run):
            code, report = runner.run_oem_readonly_audit(
                "127.0.0.1:16448",
                "adb",
            )
        self.assertEqual(0, code)
        self.assertIn("Exact alarm app-op", report)
        self.assertIn("id=deadline", report)
        self.assertIn("importance=4", report)
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

    def test_oem_audit_does_not_treat_disallow_as_allow(self) -> None:
        def fake_run(cmd, cwd=None, check=False):  # noqa: ANN001
            joined = " ".join(str(part) for part in cmd)
            text = ""
            if "getprop" in cmd:
                text = "[ro.build.version.sdk]: [35]\n"
            elif "appops" in cmd:
                text = "SCHEDULE_EXACT_ALARM: disallow"
            elif "notification" in joined:
                text = "com.example.studyassistant.journal mChannelId=deadline importance=4"
            return subprocess.CompletedProcess(cmd, 0, text, "")

        with mock.patch.object(runner, "_run", side_effect=fake_run):
            code, report = runner.run_oem_readonly_audit(
                "127.0.0.1:16448",
                "adb",
            )
        self.assertEqual(0, code)
        self.assertIn("deny/unknown", report)

    def test_instrument_command_never_enables_real_account_flag(self) -> None:
        for classes in runner.ANDROID_TEST_BATCHES.values():
            command = runner.instrument_command(
                "emulator-1",
                "adb",
                classes,
            )
            self.assertNotIn("realAccount", " ".join(command))

    def test_sync_mirror_incremental_preserves_caches_updates_changes_and_prunes_deleted(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            src = root / "src"
            dst = root / "cache" / "local_app"
            (src / "lib").mkdir(parents=True)
            (src / "android" / "app" / "src" / "main").mkdir(parents=True)
            (src / "pubspec.yaml").write_text("name: app\n", encoding="utf-8")
            (src / "lib" / "keep.dart").write_text("const a = 1;\n", encoding="utf-8")
            (src / "lib" / "drop.dart").write_text("const b = 2;\n", encoding="utf-8")
            (src / "android" / "key.properties").write_text("storeFile=placeholder.jks\n", encoding="utf-8")
            (src / "android" / "local.properties").write_text("sdk.dir=D:\\\\raw\n", encoding="utf-8")
            (src / "startup-tests.log").write_text("transient-log\n", encoding="utf-8")
            (src / "artifacts").mkdir(parents=True)
            (src / "artifacts" / "preview.apk").write_text("apk", encoding="utf-8")

            # Seed persistent caches in destination before syncing.
            (dst / "build").mkdir(parents=True)
            (dst / "build" / "sentinel.bin").write_text("cached-build", encoding="utf-8")
            (dst / "android" / ".gradle").mkdir(parents=True)
            (dst / "android" / ".gradle" / "cache.lock").write_text("cached-gradle", encoding="utf-8")
            (dst / "android" / ".kotlin" / "sessions").mkdir(parents=True)
            (dst / "android" / ".kotlin" / "sessions" / "s1").write_text("cached-kotlin", encoding="utf-8")
            (dst / ".dart_tool").mkdir(parents=True)
            (dst / ".dart_tool" / "package_config.json").write_text("{}", encoding="utf-8")
            (dst / "android" / "local.properties").write_text(
                "sdk.dir=D\\:\\\\cached\\\\sdk\n",
                encoding="utf-8",
            )

            first = runner.sync_mirror_incremental(src, dst)
            self.assertIn("lib/keep.dart", first.copied_files)
            self.assertIn("lib/drop.dart", first.copied_files)
            self.assertEqual((), first.removed_files)
            # Caches and local.properties are preserved; key.properties, logs and artifacts are never copied.
            self.assertEqual("cached-build", (dst / "build" / "sentinel.bin").read_text(encoding="utf-8"))
            self.assertEqual("cached-gradle", (dst / "android" / ".gradle" / "cache.lock").read_text(encoding="utf-8"))
            self.assertEqual("cached-kotlin", (dst / "android" / ".kotlin" / "sessions" / "s1").read_text(encoding="utf-8"))
            self.assertFalse((dst / "android" / "key.properties").exists())
            self.assertFalse((dst / "startup-tests.log").exists())
            self.assertFalse((dst / "artifacts").exists())
            self.assertEqual(
                "sdk.dir=D\\:\\\\cached\\\\sdk\n",
                (dst / "android" / "local.properties").read_text(encoding="utf-8"),
            )

            # Second sync: modify one file, delete one file, leave pubspec.yaml unchanged.
            (src / "lib" / "keep.dart").write_text("const a = 42;\n", encoding="utf-8")
            (src / "lib" / "drop.dart").unlink()
            second = runner.sync_mirror_incremental(src, dst)
            self.assertEqual(("lib/keep.dart",), second.copied_files)
            self.assertEqual(("lib/drop.dart",), second.removed_files)
            self.assertEqual(1, second.unchanged_files)
            self.assertFalse((dst / "lib" / "drop.dart").exists())
            self.assertEqual("const a = 42;\n", (dst / "lib" / "keep.dart").read_text(encoding="utf-8"))
            self.assertTrue((dst / "build" / "sentinel.bin").is_file())
            self.assertTrue((dst / "android" / ".gradle" / "cache.lock").is_file())

    def test_mirror_local_properties_rewrites_unescaped_colon_written_by_pub_get(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            mirror = root / "mirror"
            # Guarantee a colon in path on both Windows (drive letter) and POSIX CI.
            sdk = root / ("sdk" if sys.platform == "win32" else "drive:sdk")
            flutter_sdk = root / ("flutter" if sys.platform == "win32" else "drive:flutter")
            self.assertIn(":", str(sdk))
            self.assertIn(":", str(flutter_sdk))
            (sdk / "platforms" / "android-36").mkdir(parents=True)
            (flutter_sdk / "bin").mkdir(parents=True)
            (flutter_sdk / "bin" / "flutter").write_text("", encoding="utf-8")
            (mirror / "android").mkdir(parents=True)
            properties = mirror / "android" / "local.properties"
            # Simulate Flutter's unescaped colon output (e.g. D:\\campus-tools\\android)
            raw_sdk = str(sdk).replace("\\", "\\\\")
            raw_flutter = str(flutter_sdk).replace("\\", "\\\\")
            properties.write_text(
                f"sdk.dir={raw_sdk}\n"
                f"flutter.sdk={raw_flutter}\n"
                "flutter.versionName=1.8.33\n"
                "flutter.versionCode=126\n",
                encoding="utf-8",
            )
            runner.ensure_mirror_local_properties(
                mirror,
                sdk_dir=sdk,
                flutter_sdk=flutter_sdk,
            )
            rewritten = properties.read_text(encoding="utf-8")
            self.assertIn("\\:", rewritten)
            self.assertNotIn(f"sdk.dir={raw_sdk}\n", rewritten)
            self.assertNotIn(f"flutter.sdk={raw_flutter}\n", rewritten)
            values = runner._read_properties(properties)
            self.assertEqual(str(sdk), values["sdk.dir"])
            self.assertEqual(str(flutter_sdk), values["flutter.sdk"])
            self.assertEqual("1.8.33", values["flutter.versionName"])
            self.assertEqual("126", values["flutter.versionCode"])

    def test_sync_mirror_incremental_rejects_overlapping_or_nested_paths(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            src = root / "workspace" / "local_app"
            (src / "lib").mkdir(parents=True)
            sentinel = src / "lib" / "main.dart"
            sentinel.write_text("void main() {}\n", encoding="utf-8")

            for bad_dest in (src, src / "nested_cache", src.parent):
                with self.subTest(bad_dest=bad_dest):
                    with self.assertRaises(runner.ManifestError):
                        runner.sync_mirror_incremental(src, bad_dest, clean=True)
            # Source files must remain completely intact even when clean=True was passed.
            self.assertTrue(sentinel.is_file())
            self.assertEqual("void main() {}\n", sentinel.read_text(encoding="utf-8"))

    def test_local_fast_dry_run_includes_android_test_kotlin_compile_and_lint(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            stdout = StringIO()
            with contextlib.redirect_stdout(stdout):
                code = runner.main(
                    [
                        "--local-fast",
                        "--cache-dir",
                        raw,
                        "--dry-run",
                    ]
                )
            text = stdout.getvalue()
            self.assertEqual(0, code)
            self.assertIn(":app:testDebugUnitTest", text)
            self.assertIn(":app:compileDebugAndroidTestKotlin", text)
            self.assertIn(":app:lintDebug", text)
            self.assertIn("--no-daemon", text)

    def test_local_fast_runs_pub_get_then_escapes_local_properties_before_gradle(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            src = root / "repo_app"
            cache = root / "cache"
            sdk = root / ("sdk" if sys.platform == "win32" else "drive:sdk")
            flutter_sdk = root / ("flutter" if sys.platform == "win32" else "drive:flutter")
            self.assertIn(":", str(sdk))
            (src / "android").mkdir(parents=True)
            (src / "lib").mkdir(parents=True)
            (src / "test").mkdir(parents=True)
            (src / "ios").mkdir(parents=True)
            (src / "tool").mkdir(parents=True)
            (src / "android" / "build.gradle").write_text("// gradle\n", encoding="utf-8")
            (src / "lib" / "main.dart").write_text("void main() {}\n", encoding="utf-8")
            (src / "test" / "ignored_test.dart").write_text("void main() {}\n", encoding="utf-8")
            (src / "ios" / "Runner.swift").write_text("// ios\n", encoding="utf-8")
            (src / "tool" / "ignored.py").write_text("pass\n", encoding="utf-8")
            (src / "pubspec.yaml").write_text("name: demo\n", encoding="utf-8")
            (src / "pubspec.lock").write_text("packages: {}\n", encoding="utf-8")
            (sdk / "platforms" / "android-36").mkdir(parents=True)
            (flutter_sdk / "bin").mkdir(parents=True)
            (flutter_sdk / "bin" / "flutter").write_text("", encoding="utf-8")
            (flutter_sdk / "bin" / "flutter.bat").write_text("", encoding="utf-8")

            # Seed legacy non-allowlist residuals (including skipped ios/Flutter/ephemeral & __pycache__)
            # to prove upgrading an older full-mirror cache removes them completely.
            (cache / "local_app" / "ios" / "Flutter" / "ephemeral").mkdir(parents=True)
            (cache / "local_app" / "ios" / "Flutter" / "Generated.xcconfig").write_text("X=1\n", encoding="utf-8")
            (cache / "local_app" / "ios" / "Flutter" / "flutter_export_environment.sh").write_text("", encoding="utf-8")
            (cache / "local_app" / "ios" / "Flutter" / "ephemeral" / "flutter_lldbinit").write_text("", encoding="utf-8")
            (cache / "local_app" / "tool" / "__pycache__").mkdir(parents=True)
            (cache / "local_app" / "tool" / "__pycache__" / "old.pyc").write_bytes(b"00")
            (cache / "local_app" / "test").mkdir(parents=True)
            (cache / "local_app" / "test" / "legacy_test.dart").write_text("void main() {}\n", encoding="utf-8")
            (cache / "local_app" / "startup-tests.log").write_text("legacy\n", encoding="utf-8")

            events: list[str] = []

            def fake_streaming(cmd, *, cwd, env=None):  # noqa: ANN001
                joined = " ".join(cmd)
                if "pub get" in joined:
                    self.assertIn("--enforce-lockfile", cmd)
                    events.append("pub_get")
                    (cwd / ".dart_tool").mkdir(parents=True, exist_ok=True)
                    (cwd / ".dart_tool" / "package_config.json").write_text("{}", encoding="utf-8")
                    (cwd / ".flutter-plugins-dependencies").write_text("{}", encoding="utf-8")
                    # Simulate flutter pub get writing unescaped colon in local.properties
                    raw_sdk = str(sdk).replace("\\", "\\\\")
                    (cwd / "android" / "local.properties").write_text(
                        f"sdk.dir={raw_sdk}\nflutter.buildMode=debug\n",
                        encoding="utf-8",
                    )
                    return 0
                if "gradlew" in joined:
                    events.append("gradle")
                    props_text = (cwd / "local.properties").read_text(encoding="utf-8")
                    self.assertIn("\\:", props_text)
                    self.assertIn(":app:compileDebugAndroidTestKotlin", cmd)
                    return 0
                raise AssertionError(f"Unexpected command: {cmd}")

            with (
                mock.patch.object(runner, "local_app_root", return_value=src),
                mock.patch.object(runner, "_run_streaming", side_effect=fake_streaming),
                contextlib.redirect_stdout(StringIO()),
            ):
                first_code = runner.run_local_fast(
                    cache_dir=cache,
                    sdk_dir=sdk,
                    flutter_sdk=flutter_sdk,
                )
                second_code = runner.run_local_fast(
                    cache_dir=cache,
                    sdk_dir=sdk,
                    flutter_sdk=flutter_sdk,
                )

            self.assertEqual(0, first_code)
            self.assertEqual(0, second_code)
            # First run executes pub get then gradle; second warm run skips pub get and runs gradle directly.
            self.assertEqual(["pub_get", "gradle", "gradle"], events)
            # Allowlist mirroring copies lib/android/pubspec* only, excluding test/ios/tool.
            mirror_root = cache / "local_app"
            self.assertTrue((mirror_root / "lib" / "main.dart").is_file())
            self.assertFalse((mirror_root / "test").exists())
            self.assertFalse((mirror_root / "ios").exists())
            self.assertFalse((mirror_root / "tool").exists())
            self.assertFalse((mirror_root / "startup-tests.log").exists())

    def test_sync_mirror_incremental_detects_racy_same_mtime_equal_size_edit(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            src = root / "src"
            dst = root / "dst"
            (src / "lib").mkdir(parents=True)
            src_file = src / "lib" / "version.dart"
            src_file.write_text("const code = 100;\n", encoding="utf-8")

            first = runner.sync_mirror_incremental(src, dst)
            self.assertEqual(("lib/version.dart",), first.copied_files)
            pinned_stat = (dst / "lib" / "version.dart").stat()

            # Overwrite with identical byte length and force identical mtime_ns within the racy window.
            src_file.write_text("const code = 200;\n", encoding="utf-8")
            os.utime(src_file, ns=(pinned_stat.st_atime_ns, pinned_stat.st_mtime_ns))

            second = runner.sync_mirror_incremental(src, dst)
            self.assertEqual(("lib/version.dart",), second.copied_files)
            self.assertEqual("const code = 200;\n", (dst / "lib" / "version.dart").read_text(encoding="utf-8"))

    def test_properties_unescape_handles_unicode_and_escaped_delimiters_without_double_backslash(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            mirror = root / "mirror"
            (mirror / "android").mkdir(parents=True)
            props = mirror / "android" / "local.properties"
            props.write_text(
                "custom.note=D\\:\\\\codex\\\\\\u5b66\\u4e60\\=ok\\#1\n",
                encoding="utf-8",
            )
            parsed = runner._read_properties(props)
            self.assertEqual("D:\\codex\\学习=ok#1", parsed["custom.note"])
            runner._write_properties(props, parsed)
            reparsed = runner._read_properties(props)
            self.assertEqual(parsed, reparsed)

    def test_default_local_fast_dir_requires_campus_tools_directory(self) -> None:
        with mock.patch.object(Path, "is_dir", return_value=False):
            fallback = runner._default_local_fast_dir()
        self.assertEqual(Path(tempfile.gettempdir()) / "cx-android-cache", fallback)

    def test_local_fast_retries_pub_get_after_failure_missing_plugins_or_sdk_switch(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            src = root / "repo_app"
            cache = root / "cache"
            sdk = root / ("sdk" if sys.platform == "win32" else "drive:sdk")
            flutter_a = root / "flutter_a"
            flutter_b = root / "flutter_b"
            (src / "android").mkdir(parents=True)
            (src / "android" / "build.gradle").write_text("// gradle\n", encoding="utf-8")
            (src / "pubspec.yaml").write_text("name: demo\nversion: 1.0.0+1\n", encoding="utf-8")
            (src / "pubspec.lock").write_text("packages: {}\n", encoding="utf-8")
            (sdk / "platforms" / "android-36").mkdir(parents=True)
            for flutter_sdk in (flutter_a, flutter_b):
                (flutter_sdk / "bin").mkdir(parents=True)
                (flutter_sdk / "bin" / "flutter").write_text("", encoding="utf-8")
                (flutter_sdk / "bin" / "flutter.bat").write_text("", encoding="utf-8")
                (flutter_sdk / "version").write_text("3.44.9\n", encoding="utf-8")

            events: list[str] = []
            fail_next_pub = {"value": False}
            plugins_json = '{"plugins":{"android":[{"name":"shared_preferences_android"}]}}'

            def fake_streaming(cmd, *, cwd, env=None):  # noqa: ANN001
                joined = " ".join(cmd)
                if "pub get" in joined:
                    events.append("pub_get")
                    if fail_next_pub["value"]:
                        fail_next_pub["value"] = False
                        return 1
                    (cwd / ".dart_tool").mkdir(parents=True, exist_ok=True)
                    (cwd / ".dart_tool" / "package_config.json").write_text("{}", encoding="utf-8")
                    (cwd / ".flutter-plugins-dependencies").write_text(plugins_json, encoding="utf-8")
                    reg = (
                        cwd
                        / "android"
                        / "app"
                        / "src"
                        / "main"
                        / "java"
                        / "io"
                        / "flutter"
                        / "plugins"
                        / "GeneratedPluginRegistrant.java"
                    )
                    reg.parent.mkdir(parents=True, exist_ok=True)
                    reg.write_text("class GeneratedPluginRegistrant {}\n", encoding="utf-8")
                    return 0
                if "gradlew" in joined:
                    events.append("gradle")
                    return 0
                raise AssertionError(f"Unexpected command: {cmd}")

            with (
                mock.patch.object(runner, "local_app_root", return_value=src),
                mock.patch.object(runner, "_run_streaming", side_effect=fake_streaming),
                contextlib.redirect_stdout(StringIO()),
                contextlib.redirect_stderr(StringIO()),
            ):
                # 1. Warm initial cache with flutter_a.
                self.assertEqual(0, runner.run_local_fast(cache_dir=cache, sdk_dir=sdk, flutter_sdk=flutter_a))
                # 2. Bump pubspec.yaml, fail pub get, then revert pubspec.yaml back to 1.0.0+1 ->
                #    because old stamp was unlinked before pub get ran, retry MUST still run pub get!
                (src / "pubspec.yaml").write_text("name: demo\nversion: 1.0.1+20\n", encoding="utf-8")
                fail_next_pub["value"] = True
                self.assertEqual(1, runner.run_local_fast(cache_dir=cache, sdk_dir=sdk, flutter_sdk=flutter_a))
                (src / "pubspec.yaml").write_text("name: demo\nversion: 1.0.0+1\n", encoding="utf-8")
                self.assertEqual(0, runner.run_local_fast(cache_dir=cache, sdk_dir=sdk, flutter_sdk=flutter_a))
                # 3. Force pub get and fail -> next normal run without --force-pub-get MUST re-run pub get.
                fail_next_pub["value"] = True
                self.assertEqual(
                    1,
                    runner.run_local_fast(
                        cache_dir=cache,
                        sdk_dir=sdk,
                        flutter_sdk=flutter_a,
                        force_pub_get=True,
                    ),
                )
                self.assertEqual(0, runner.run_local_fast(cache_dir=cache, sdk_dir=sdk, flutter_sdk=flutter_a))
                # 4. Delete GeneratedPluginRegistrant.java while Android plugins exist -> must re-run pub get.
                (
                    cache
                    / "local_app"
                    / "android"
                    / "app"
                    / "src"
                    / "main"
                    / "java"
                    / "io"
                    / "flutter"
                    / "plugins"
                    / "GeneratedPluginRegistrant.java"
                ).unlink()
                self.assertEqual(0, runner.run_local_fast(cache_dir=cache, sdk_dir=sdk, flutter_sdk=flutter_a))
                # 5. Upgrade Flutter SDK version in-place -> stamp mismatch must trigger pub get.
                (flutter_a / "version").write_text("3.45.0\n", encoding="utf-8")
                self.assertEqual(0, runner.run_local_fast(cache_dir=cache, sdk_dir=sdk, flutter_sdk=flutter_a))
                # 6. Switch Flutter SDK directory -> stamp mismatch must trigger pub get.
                self.assertEqual(0, runner.run_local_fast(cache_dir=cache, sdk_dir=sdk, flutter_sdk=flutter_b))

            self.assertEqual(
                [
                    "pub_get",
                    "gradle",
                    "pub_get",  # failed attempt after edit
                    "pub_get",  # retried even after reverting pubspec.yaml
                    "gradle",
                    "pub_get",  # failed --force-pub-get
                    "pub_get",  # retried on normal run after --force-pub-get failure
                    "gradle",
                    "pub_get",  # missing GeneratedPluginRegistrant.java
                    "gradle",
                    "pub_get",  # in-place flutter version upgrade
                    "gradle",
                    "pub_get",  # switched flutter SDK path
                    "gradle",
                ],
                events,
            )

    def test_local_fast_rejects_device_serial_combination(self) -> None:
        stdout = StringIO()
        stderr = StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = runner.main(["--local-fast", "--serial", "emulator-1"])
        self.assertEqual(2, code)
        self.assertIn("--local-fast", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
