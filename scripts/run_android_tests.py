#!/usr/bin/env python3
"""Run Android instrumentation tests in isolated batches with a hard safety guard."""

from __future__ import annotations

import argparse
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
import os
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
PROTECTED_FIRST_INSTALL_TIMES = {"2026-11-04 19:05:10"}
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
    "batch4_api_matrix_and_doze": (
        "ReminderApiMatrixTest",
    ),
}


class ManifestError(RuntimeError):
    pass


@dataclass
class BatchResult:
    name: str
    serial: str = ""
    doze: str = "—"
    passed: int = 0
    failed: int = 0
    skipped: int = 0
    assumption_skipped: int = 0
    execution_error: str | None = None


@dataclass(frozen=True)
class DeviceInfo:
    serial: str
    sdk_int: int | None
    abi: str
    manufacturer: str
    model: str
    timezone: str
    is_emulator: bool
    installed_version: str
    installed_code: str
    first_install_time: str


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


def normalize_serials(values: Sequence[str] | None) -> list[str]:
    serials: list[str] = []
    for value in values or ():
        for part in value.split(","):
            serial = part.strip()
            if serial and serial not in serials:
                serials.append(serial)
    return serials


def _shell(serial: str, adb: str, *args: str) -> str:
    completed = _run([adb, "-s", serial, "shell", *args])
    if completed.returncode != 0:
        raise ManifestError(
            f"adb shell {' '.join(args)} failed for {serial}: "
            f"{completed.stderr.strip() or completed.stdout.strip()}"
        )
    return completed.stdout


def _parse_getprop(text: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in text.splitlines():
        match = re.match(r"^\[([^\]]+)\]: \[(.*)\]$", line.strip())
        if match:
            values[match.group(1)] = match.group(2)
    return values


def probe_device(serial: str, adb: str) -> DeviceInfo:
    """Read-only device identity used before any destructive command."""

    properties = _parse_getprop(_shell(serial, adb, "getprop"))
    package_dump = _shell(
        serial,
        adb,
        "dumpsys",
        "package",
        PACKAGE,
    )
    version_name = ""
    version_code = ""
    first_install = ""
    for line in package_dump.splitlines():
        stripped = line.strip()
        if stripped.startswith("versionName=") and not version_name:
            version_name = stripped.split("=", 1)[1]
        elif stripped.startswith("versionCode=") and not version_code:
            version_code = stripped.split("=", 1)[1].split()[0]
        elif stripped.startswith("firstInstallTime=") and not first_install:
            first_install = stripped.split("=", 1)[1].strip()
    characteristics = properties.get("ro.build.characteristics", "")
    is_emulator = (
        serial.startswith(("emulator-", "127.0.0.1:"))
        or properties.get("ro.kernel.qemu") == "1"
        or "emulator" in characteristics
    )
    sdk_raw = properties.get("ro.build.version.sdk", "")
    try:
        sdk_int = int(sdk_raw)
    except ValueError:
        sdk_int = None
    return DeviceInfo(
        serial=serial,
        sdk_int=sdk_int,
        abi=properties.get("ro.product.cpu.abi", ""),
        manufacturer=properties.get("ro.product.manufacturer", ""),
        model=properties.get("ro.product.model", ""),
        timezone=properties.get("persist.sys.timezone", ""),
        is_emulator=is_emulator,
        installed_version=version_name,
        installed_code=version_code,
        first_install_time=first_install,
    )


def validate_destructive_target(
    info: DeviceInfo,
    *,
    allow_wipe_physical: bool,
) -> str | None:
    if info.serial in PROTECTED_SERIALS:
        return (
            f"Refusing protected data-preserving device {info.serial}. "
            "Use a disposable emulator for instrumentation tests."
        )
    if info.first_install_time in PROTECTED_FIRST_INSTALL_TIMES:
        return (
            f"Refusing device {info.serial} with protected "
            f"firstInstallTime={info.first_install_time}."
        )
    if not info.is_emulator and not allow_wipe_physical:
        return (
            f"Refusing unknown or physical device {info.serial}; "
            "use --oem-readonly-audit for a read-only audit or pass "
            "--allow-wipe-physical after confirming the target."
        )
    return None


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


def _properties_unescape(value: str) -> str:
    return value.replace("\\:", ":").replace("\\\\", "\\")


def _properties_escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace(":", "\\:")


def _read_properties(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.is_file():
        return values
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = _properties_unescape(value.strip())
    return values


def _write_properties(path: Path, values: Mapping[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"{key}={_properties_escape(value)}" for key, value in values.items()]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _has_android_36(path: Path) -> bool:
    return (path / "platforms" / "android-36").is_dir()


def ensure_mirror_local_properties(
    mirror_root: Path,
    *,
    sdk_dir: Path | None,
    flutter_sdk: Path | None,
) -> None:
    """Repair only the mirror copy; the shared worktree is never written."""

    if mirror_root.resolve() == local_app_root().resolve():
        return
    properties_path = mirror_root / "android" / "local.properties"
    if not properties_path.parent.is_dir():
        return
    current = _read_properties(properties_path)
    current_sdk = current.get("sdk.dir", "")
    sdk_candidates: list[Path] = []
    if sdk_dir is not None:
        sdk_candidates.append(sdk_dir)
    for key in ("ANDROID_SDK_ROOT", "ANDROID_HOME"):
        value = os.environ.get(key)
        if value:
            sdk_candidates.append(Path(value))
    if current_sdk:
        sdk_candidates.append(Path(current_sdk))
    sdk_candidates.append(Path.home() / "AppData" / "Local" / "Android" / "Sdk")
    chosen_sdk = next(
        (candidate for candidate in sdk_candidates if _has_android_36(candidate)),
        None,
    )
    changed = False
    if chosen_sdk is not None and (
        not current_sdk
        or Path(current_sdk).resolve() != chosen_sdk.resolve()
    ):
        current["sdk.dir"] = str(chosen_sdk)
        changed = True
    current_flutter = current.get("flutter.sdk", "")
    if flutter_sdk is not None and Path(flutter_sdk).is_dir():
        if not current_flutter or not (Path(current_flutter) / "bin" / "flutter").exists():
            current["flutter.sdk"] = str(flutter_sdk)
            changed = True
    if changed:
        _write_properties(properties_path, current)


def _build_root(
    work_dir: Path,
    *,
    sdk_dir: Path | None = None,
    flutter_sdk: Path | None = None,
) -> Path:
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
    ensure_mirror_local_properties(
        destination,
        sdk_dir=sdk_dir,
        flutter_sdk=flutter_sdk,
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


def enter_doze(serial: str, adb: str) -> str:
    baseline = _deep_state(
        _shell(serial, adb, "dumpsys", "deviceidle", "get", "deep")
    )
    _shell(serial, adb, "dumpsys", "battery", "unplug")
    _shell(serial, adb, "dumpsys", "deviceidle", "force-idle")
    entered = _deep_state(
        _shell(serial, adb, "dumpsys", "deviceidle", "get", "deep")
    )
    if entered == "IDLE":
        return f"IDLE (from {baseline})"
    return f"unsupported ({' '.join(entered.split())})"


def _deep_state(text: str) -> str:
    text = text.replace("|", "/")
    match = re.search(r"deep state:\s*([A-Z-]+)", text, re.IGNORECASE)
    if match:
        return match.group(1).upper()
    stripped = text.strip().upper()
    if stripped == "IDLE" or stripped.endswith(" IDLE"):
        return "IDLE"
    if stripped == "ACTIVE" or stripped.endswith(" ACTIVE"):
        return "ACTIVE"
    return " ".join(stripped.splitlines()[0].split()) if stripped else "unknown"


def exit_doze(serial: str, adb: str) -> None:
    errors: list[str] = []
    for args in (
        ("dumpsys", "deviceidle", "unforce"),
        ("dumpsys", "battery", "reset"),
    ):
        completed = _run([adb, "-s", serial, "shell", *args])
        if completed.returncode != 0:
            errors.append(
                completed.stderr.strip()
                or completed.stdout.strip()
                or " ".join(args)
            )
    if errors:
        raise ManifestError(
            f"Doze reset failed for {serial}: {'; '.join(errors)}"
        )


def run_with_doze(
    serial: str,
    adb: str,
    action,
) -> tuple[list[BatchResult], str]:
    try:
        doze_state = enter_doze(serial, adb)
        return action(), f"{doze_state} → reset"
    finally:
        exit_doze(serial, adb)


def _notification_channel_summary(text: str) -> str:
    if PACKAGE not in text:
        return "unknown"
    lines = text.splitlines()
    start = next(
        (index for index, line in enumerate(lines) if PACKAGE in line),
        0,
    )
    channel_id = ""
    importance = ""
    for line in lines[start : start + 80]:
        if not channel_id:
            match = re.search(
                r"(?:mChannelId|channelId|mId)=([^\s,}]+)",
                line,
            )
            if match:
                channel_id = match.group(1).strip().strip("'\"")
        if not importance:
            match = re.search(r"(?:mImportance|importance)=(\d+)", line)
            if match:
                importance = match.group(1)
        if channel_id and importance:
            break
    details = []
    if channel_id:
        details.append(f"id={channel_id}")
    if importance:
        details.append(f"importance={importance}")
    return "present " + " ".join(details) if details else "present"


def run_oem_readonly_audit(serial: str, adb: str) -> tuple[int, str]:
    """Read-only OEM diagnostics; never uninstalls, installs or instruments."""

    try:
        info = probe_device(serial, adb)
    except ManifestError as error:
        return 1, f"[FAIL] {error}"
    appops = _run(
        [adb, "-s", serial, "shell", "appops", "get", PACKAGE,
         "SCHEDULE_EXACT_ALARM"]
    )
    whitelist = _run(
        [adb, "-s", serial, "shell", "dumpsys", "deviceidle", "whitelist"]
    )
    alarms = _run([adb, "-s", serial, "shell", "dumpsys", "alarm"])
    notifications = _run(
        [adb, "-s", serial, "shell", "dumpsys", "notification"]
    )
    appops_text = appops.stdout if appops.returncode == 0 else "unknown"
    whitelist_text = whitelist.stdout if whitelist.returncode == 0 else ""
    alarm_text = alarms.stdout if alarms.returncode == 0 else ""
    notification_text = (
        notifications.stdout if notifications.returncode == 0 else ""
    )
    alarm_lines = [
        line for line in alarm_text.splitlines() if PACKAGE in line
    ]
    rows = [
        ("Serial", info.serial),
        ("API", str(info.sdk_int or "unknown")),
        ("ABI", info.abi or "unknown"),
        ("Device", f"{info.manufacturer} {info.model}".strip() or "unknown"),
        ("Timezone", info.timezone or "unknown"),
        ("Installed", f"{info.installed_version} ({info.installed_code})"),
        ("First install", info.first_install_time or "unknown"),
        (
            "Exact alarm app-op",
            "allow" if re.search(r"\ballow\b", appops_text) else "deny/unknown",
        ),
        (
            "Battery whitelist",
            "yes" if PACKAGE in whitelist_text else "no",
        ),
        (
            "Alarm entries",
            f"{len(alarm_lines)} "
            f"(deadline={any('ASSIGNMENT_DEADLINE' in line or 'ScheduledNotificationReceiver' in line for line in alarm_lines)})",
        ),
        ("Reminder channel", _notification_channel_summary(notification_text)),
    ]
    lines = ["| Field | Value |", "| --- | --- |"]
    lines.extend(f"| {key} | {value} |" for key, value in rows)
    return 0, "\n".join(lines)


def _run_batch(
    serial: str,
    adb: str,
    app_apk: Path,
    test_apk: Path,
    name: str,
    classes: Sequence[str],
) -> list[BatchResult]:
    for cmd in batch_commands(serial, adb, app_apk, test_apk, classes):
        completed = _run(cmd)
        if "install" in cmd and completed.returncode != 0:
            print(completed.stdout)
            print(completed.stderr, file=sys.stderr)
            return [
                BatchResult(
                    name=name,
                    serial=serial,
                    execution_error="APK install failed",
                )
            ]
        if "instrument" in cmd:
            print(completed.stdout)
            if completed.stderr.strip():
                print(completed.stderr, file=sys.stderr)
            result = summarize_results(
                name, completed.stdout, completed.returncode
            )
            result.serial = serial
            return [result]
    return [
        BatchResult(
            name=name,
            serial=serial,
            execution_error="instrumentation command was not executed",
        )
    ]


def _default_work_dir() -> Path:
    drive_d = Path("D:/")
    if drive_d.exists():
        return Path("D:/campus-tools/build-work/androidtest-run")
    return Path(tempfile.gettempdir()) / "androidtest-run"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-manifest-only", action="store_true")
    parser.add_argument("--serial", action="append")
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--work-dir", type=Path)
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--sdk-dir", type=Path)
    parser.add_argument("--flutter-sdk", type=Path)
    parser.add_argument("--allow-wipe-physical", action="store_true")
    parser.add_argument("--doze-probe", action="store_true")
    parser.add_argument("--oem-readonly-audit", action="store_true")
    args = parser.parse_args(argv)

    try:
        batches = verify_batch_manifest(default_android_test_dir())
        total = sum(len(items) for items in batches.values())
        print(f"[PASS] Android test manifest covers {total} classes in {len(batches)} batches.")
        if args.verify_manifest_only:
            return 0

        serials = normalize_serials(args.serial)
        if not serials:
            print("[FAIL] --serial is required unless --verify-manifest-only is used.", file=sys.stderr)
            return 2
        if args.oem_readonly_audit:
            if args.doze_probe or args.allow_wipe_physical or args.dry_run:
                print(
                    "[FAIL] --oem-readonly-audit cannot be combined with "
                    "--doze-probe, --allow-wipe-physical or --dry-run.",
                    file=sys.stderr,
                )
                return 2
            results = 0
            for serial in serials:
                code, report = run_oem_readonly_audit(serial, args.adb)
                print(f"\n### OEM read-only audit · {serial}\n")
                print(report)
                results = max(results, code)
            return results
        for serial in serials:
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
            for serial in serials:
                _print_commands(
                    serial,
                    args.adb,
                    app_root / "build/app/outputs/flutter-apk/app-debug.apk",
                    app_root / "build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk",
                    batches,
                )
            if args.doze_probe:
                print("[DRY-RUN] batch4 will enter and reset Doze")
            return 0

        if not args.skip_build:
            build_root = _build_root(
                args.work_dir or _default_work_dir(),
                sdk_dir=args.sdk_dir,
                flutter_sdk=args.flutter_sdk,
            )
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
        devices: list[DeviceInfo] = []
        for serial in serials:
            info = probe_device(serial, args.adb)
            refusal = validate_destructive_target(
                info,
                allow_wipe_physical=args.allow_wipe_physical,
            )
            if refusal is not None:
                print(f"[FAIL] {refusal}", file=sys.stderr)
                return 2
            devices.append(info)

        results: list[BatchResult] = []
        for info in devices:
            serial = info.serial
            install_failed = False
            for name, classes in batches.items():
                print(
                    f"\n=== {serial} · {name} ({len(classes)} classes) ===",
                    flush=True,
                )
                try:
                    if args.doze_probe and name == "batch4_api_matrix_and_doze":
                        batch_results, doze_state = run_with_doze(
                            serial,
                            args.adb,
                            lambda: _run_batch(
                                serial,
                                args.adb,
                                app_apk,
                                test_apk,
                                name,
                                classes,
                            ),
                        )
                        for result in batch_results:
                            result.doze = doze_state
                        results.extend(batch_results)
                    else:
                        batch_results = _run_batch(
                            serial,
                            args.adb,
                            app_apk,
                            test_apk,
                            name,
                            classes,
                        )
                        results.extend(batch_results)
                except ManifestError as error:
                    results.append(
                        BatchResult(
                            name=name,
                            serial=serial,
                            execution_error=str(error),
                        )
                    )
                if any(
                    result.execution_error == "APK install failed"
                    for result in results
                    if result.serial == serial and result.name == name
                ):
                    install_failed = True
                    break
            if install_failed:
                continue

        print("\n### Android instrumentation summary\n")
        print(
            "| Serial | API | ABI | Device | Batch | Passed | Failed | "
            "Skipped | Assumption skip | Doze | Error |"
        )
        print(
            "| --- | ---: | --- | --- | --- | ---: | ---: | ---: | "
            "---: | --- | --- |"
        )
        by_serial = {info.serial: info for info in devices}
        for result in results:
            info = by_serial.get(result.serial)
            print(
                f"| {result.serial} | {(info.sdk_int if info else None) or '?'} | "
                f"{info.abi if info else '?'} | "
                f"{(info.manufacturer + ' ' + info.model).strip() if info else '?'} | "
                f"{result.name} | {result.passed} | {result.failed} | "
                f"{result.skipped} | {result.assumption_skipped} | "
                f"{result.doze} | "
                f"{result.execution_error or ''} |"
            )
        failed = any(
            result.failed > 0 or result.execution_error is not None
            for result in results
        )
        if len(results) != len(devices) * len(batches):
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
