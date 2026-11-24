#!/usr/bin/env python3
"""Run Android instrumentation tests in isolated batches with a hard safety guard."""

from __future__ import annotations

import argparse
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

PACKAGE = "com.example.studyassistant.journal"
TEST_PACKAGE = f"{PACKAGE}.test"
TEST_CLASS_PACKAGE = "com.example.studyassistant"
TEST_RUNNER = "androidx.test.runner.AndroidJUnitRunner"
PROTECTED_SERIALS = {"127.0.0.1:16448"}
CRASH_MARKERS = ("FAILURES!!!", "Process crashed")
CRASH_PREFIXES = (
    "INSTRUMENTATION_STATUS: Error=",
    "INSTRUMENTATION_STATUS: shortMsg=",
    "INSTRUMENTATION_RESULT: shortMsg=",
    "INSTRUMENTATION_FAILED:",
)

ANDROID_TEST_BATCHES: dict[str, tuple[str, ...]] = {
    "batch1_channel_and_fresh_install": (
        "AssignmentNotificationPublisherTest",
        "ReminderHistoryControlTest",
    ),
    "batch2_reminder_and_background": (
        "Batch2BAlarmReconcileTest",
        "BackgroundReminderBridgeTest",
        "LegacyAssignmentCacheTest",
        "LegacyAssignmentNotificationMigratorTest",
        "NotificationSignalClaimTest",
        "NotificationWorkSchedulerTest",
        "ReminderAggregateNotificationTest",
        "ReminderClickRoutingTest",
        "ReminderDatabaseAccountTest",
        "ReminderDatabaseMigrationTest",
        "ReminderDatabaseRetentionTest",
        "ReminderHistoryDatabaseTest",
        "ReminderSourceScopeTest",
    ),
    "batch3_widget_and_boundaries": (
        "AssignmentWidgetProviderTest",
        "ExternalUrlBoundaryTest",
        "FeedbackEmailIntentTest",
        "FeedbackEmailLaunchTest",
        "HeadlessFlutterEngineTest",
        "RealAccountHeadlessEntryTest",
    ),
}


class ManifestError(RuntimeError):
    pass


@dataclass
class BatchResult:
    name: str
    passed: int = 0
    failed: int = 0
    skipped: int = 0
    assumption_skipped: int = 0
    execution_error: str | None = None


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def local_app_root() -> Path:
    return repo_root() / "study_assistant-1.1.0" / "local_app"


def default_android_test_dir() -> Path:
    return (
        local_app_root()
        / "android"
        / "app"
        / "src"
        / "androidTest"
        / "kotlin"
        / "com"
        / "example"
        / "studyassistant"
    )


def verify_batch_manifest(
    android_test_dir: Path,
    batches: Mapping[str, Sequence[str]] | None = None,
) -> dict[str, tuple[str, ...]]:
    """Require every on-disk *Test.kt class in exactly one configured batch."""

    configured = {
        name: tuple(classes)
        for name, classes in (batches or ANDROID_TEST_BATCHES).items()
    }
    if not android_test_dir.is_dir():
        raise ManifestError(f"Android test directory not found: {android_test_dir}")
    actual = {path.stem for path in android_test_dir.glob("*Test.kt") if path.is_file()}
    if not actual:
        raise ManifestError(f"No *Test.kt files found in {android_test_dir}")
    registered: list[str] = []
    for name, classes in configured.items():
        if not name or not classes:
            raise ManifestError(f"Batch {name!r} must have a name and at least one class")
        registered.extend(classes)
    duplicates = sorted(
        {name for name in registered if registered.count(name) > 1}
    )
    if duplicates:
        raise ManifestError(f"Classes registered in more than one slot: {duplicates}")
    missing = sorted(actual - set(registered))
    unknown = sorted(set(registered) - actual)
    if missing:
        raise ManifestError(f"Unregistered *Test.kt classes: {missing}")
    if unknown:
        raise ManifestError(f"Configured classes without source files: {unknown}")
    return configured


def parse_instrumentation_output(text: str) -> dict[tuple[str, str], int]:
    """Return the final INSTRUMENTATION_STATUS_CODE for each test."""

    current: dict[str, str] = {}
    results: dict[tuple[str, str], int] = {}
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("INSTRUMENTATION_STATUS: "):
            payload = line[len("INSTRUMENTATION_STATUS: ") :]
            key, sep, value = payload.partition("=")
            if sep and key in {"class", "test"}:
                current[key] = value
        elif line.startswith("INSTRUMENTATION_STATUS_CODE: "):
            try:
                code = int(line.split(":", 1)[1].strip())
            except ValueError:
                continue
            test_class = current.get("class")
            test_name = current.get("test")
            if test_class and test_name:
                results[(test_class, test_name)] = code
    return results


def detect_execution_error(output: str) -> str | None:
    """Return the first instrumentation crash marker, if the run did not finish."""

    for line in output.splitlines():
        stripped = line.strip()
        if stripped.startswith(CRASH_PREFIXES):
            return stripped
    for marker in CRASH_MARKERS:
        if marker in output:
            return marker
    return None


def summarize_results(name: str, output: str, returncode: int) -> BatchResult:
    parsed = parse_instrumentation_output(output)
    result = BatchResult(name=name, execution_error=detect_execution_error(output))
    for code in parsed.values():
        if code == 0:
            result.passed += 1
        elif code in {-1, -2}:
            result.failed += 1
        elif code == -4:
            result.skipped += 1
            result.assumption_skipped += 1
        elif code == -3:
            result.skipped += 1
    if not parsed:
        ok_match = re.search(r"OK \((\d+) tests?\)", output)
        if ok_match:
            result.passed = int(ok_match.group(1))
        elif returncode != 0 and result.execution_error is None:
            result.failed = 1
        else:
            result.execution_error = (
                result.execution_error or "instrumentation reported no test results"
            )
    unfinished = next(
        (
            f"{test_class}.{test_name}"
            for (test_class, test_name), code in parsed.items()
            if code == 1
        ),
        None,
    )
    if unfinished is not None and result.execution_error is None:
        result.execution_error = f"instrumentation did not finish {unfinished}"
    if (
        returncode != 0
        and result.failed == 0
        and result.execution_error is None
    ):
        result.execution_error = f"instrumentation exited with {returncode}"
    return result


def _run(cmd: list[str], cwd: Path | None = None, *, check: bool = False) -> subprocess.CompletedProcess[str]:
    print("+ " + " ".join(str(part) for part in cmd), flush=True)
    return subprocess.run(
        cmd,
        cwd=cwd,
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        check=check,
    )


def qualified_classes(classes: Sequence[str]) -> list[str]:
    return [f"{TEST_CLASS_PACKAGE}.{name}" for name in classes]


def instrument_command(
    serial: str, adb: str, classes: Sequence[str]
) -> list[str]:
    return [
        adb,
        "-s",
        serial,
        "shell",
        "am",
        "instrument",
        "-w",
        "-r",
        "-e",
        "class",
        ",".join(qualified_classes(classes)),
        f"{TEST_PACKAGE}/{TEST_RUNNER}",
    ]


def batch_commands(
    serial: str,
    adb: str,
    app_apk: Path,
    test_apk: Path,
    classes: Sequence[str],
) -> list[list[str]]:
    return [
        [adb, "-s", serial, "uninstall", PACKAGE],
        [adb, "-s", serial, "uninstall", TEST_PACKAGE],
        [adb, "-s", serial, "install", "-r", str(app_apk)],
        [adb, "-s", serial, "install", "-r", str(test_apk)],
        instrument_command(serial, adb, classes),
    ]


def _print_commands(serial: str, adb: str, app_apk: Path, test_apk: Path, batches: Mapping[str, Sequence[str]]) -> None:
    for name, classes in batches.items():
        print(f"[DRY-RUN] {name}")
        for cmd in batch_commands(serial, adb, app_apk, test_apk, classes):
            print("+ " + " ".join(cmd))


def _build_root(work_dir: Path) -> Path:
    source = local_app_root()
    if str(source).isascii():
        return source
    if not str(work_dir).isascii():
        raise ManifestError(f"--work-dir must be ASCII: {work_dir}")
    destination = work_dir / "local_app"
    if destination.exists():
        shutil.rmtree(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(
        source,
        destination,
        ignore=shutil.ignore_patterns("build", ".gradle"),
    )
    package_config = destination / "pubspec.yaml"
    if not package_config.is_file():
        raise ManifestError(f"Mirror is incomplete: {package_config} missing")
    return destination


def _gradle_command(app_root: Path) -> list[str]:
    if sys.platform == "win32":
        return [
            "cmd",
            "/c",
            str(app_root / "android" / "gradlew.bat"),
            ":app:assembleDebug",
            ":app:assembleDebugAndroidTest",
            "--no-daemon",
        ]
    return [
        str(app_root / "android" / "gradlew"),
        ":app:assembleDebug",
        ":app:assembleDebugAndroidTest",
        "--no-daemon",
    ]


def _find_apk(app_root: Path, name: str) -> Path:
    matches = sorted(app_root.glob(f"build/**/{name}"))
    if not matches:
        raise ManifestError(f"APK not found after build: {name}")
    return matches[0]


def _default_work_dir() -> Path:
    drive_d = Path("D:/")
    if drive_d.exists():
        return Path("D:/campus-tools/build-work/androidtest-run")
    return Path(tempfile.gettempdir()) / "androidtest-run"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-manifest-only", action="store_true")
    parser.add_argument("--serial")
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--work-dir", type=Path)
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    try:
        batches = verify_batch_manifest(default_android_test_dir())
        total = sum(len(items) for items in batches.values())
        print(f"[PASS] Android test manifest covers {total} classes in {len(batches)} batches.")
        if args.verify_manifest_only:
            return 0

        serial = (args.serial or "").strip()
        if not serial:
            print("[FAIL] --serial is required unless --verify-manifest-only is used.", file=sys.stderr)
            return 2
        if serial in PROTECTED_SERIALS:
            print(
                f"[FAIL] Refusing protected data-preserving device {serial}. "
                "Use a disposable emulator for instrumentation tests.",
                file=sys.stderr,
            )
            return 2

        app_root = local_app_root()
        if args.dry_run:
            print(f"[DRY-RUN] project root: {app_root}")
            if not args.skip_build:
                print("+ " + " ".join(_gradle_command(app_root)))
            _print_commands(
                serial,
                args.adb,
                app_root / "build/app/outputs/flutter-apk/app-debug.apk",
                app_root / "build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk",
                batches,
            )
            return 0

        if not args.skip_build:
            build_root = _build_root(args.work_dir or _default_work_dir())
            build = _run(
                _gradle_command(build_root),
                cwd=build_root / "android",
            )
            if build.returncode != 0:
                print(build.stdout)
                print(build.stderr, file=sys.stderr)
                print("[FAIL] Gradle build failed.", file=sys.stderr)
                return 1
        else:
            build_root = (
                args.work_dir / "local_app" if args.work_dir else app_root
            )

        app_apk = _find_apk(build_root, "app-debug.apk")
        test_apk = _find_apk(build_root, "app-debug-androidTest.apk")
        results: list[BatchResult] = []
        install_failed = False
        for name, classes in batches.items():
            print(f"\n=== {name} ({len(classes)} classes) ===", flush=True)
            for cmd in batch_commands(
                serial, args.adb, app_apk, test_apk, classes
            ):
                completed = _run(cmd)
                if "install" in cmd and completed.returncode != 0:
                    print(completed.stdout)
                    print(completed.stderr, file=sys.stderr)
                    results.append(
                        BatchResult(
                            name=name, execution_error="APK install failed"
                        )
                    )
                    install_failed = True
                    break
                if "instrument" in cmd:
                    print(completed.stdout)
                    if completed.stderr.strip():
                        print(completed.stderr, file=sys.stderr)
                    results.append(
                        summarize_results(
                            name, completed.stdout, completed.returncode
                        )
                    )
            if install_failed:
                break

        print("\n### Android instrumentation summary\n")
        print("| Batch | Passed | Failed | Skipped | Assumption skip | Error |")
        print("| --- | ---: | ---: | ---: | ---: | --- |")
        for result in results:
            print(
                f"| {result.name} | {result.passed} | {result.failed} | "
                f"{result.skipped} | {result.assumption_skipped} | "
                f"{result.execution_error or ''} |"
            )
        failed = any(
            result.failed > 0 or result.execution_error is not None
            for result in results
        )
        if len(results) != len(batches):
            failed = True
        if failed:
            print("\n[FAIL] One or more Android instrumentation batches failed.", file=sys.stderr)
            return 1
        print("\n[PASS] All Android instrumentation batches completed.")
        return 0
    except ManifestError as error:
        print(f"[FAIL] {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
