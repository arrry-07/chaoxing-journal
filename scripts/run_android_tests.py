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
import stat
import subprocess
import sys
import tempfile
import time

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

LOCAL_FAST_TASKS: tuple[str, ...] = (
    ":app:testDebugUnitTest",
    ":app:compileDebugAndroidTestKotlin",
    ":app:lintDebug",
)

MIRROR_SKIP_PREFIXES: tuple[tuple[str, ...], ...] = (
    ("artifacts",),
    ("build",),
    (".gradle",),
    (".kotlin",),
    (".dart_tool",),
    (".idea",),
    (".flutter-plugins",),
    (".flutter-plugins-dependencies",),
    ("android", ".gradle"),
    ("android", ".kotlin"),
    ("android", "build"),
    ("android", ".cxx"),
    ("android", "local.properties"),
    ("android", "key.properties"),
    ("android", "app", "build"),
    ("android", "app", ".cxx"),
    ("android", "app", "src", "main", "java", "io", "flutter", "plugins"),
    ("ios", "Flutter", "ephemeral"),
    ("ios", "Flutter", "Generated.xcconfig"),
    ("ios", "Flutter", "flutter_export_environment.sh"),
)

MIRROR_SKIP_NAMES: frozenset[str] = frozenset({
    ".git",
    ".kotlin",
    "__pycache__",
    ".DS_Store",
})

MIRROR_SKIP_SUFFIXES: tuple[str, ...] = (
    ".log",
    ".apk",
    ".aab",
    ".jks",
    ".keystore",
    ".idsig",
)


@dataclass(frozen=True)
class SyncReport:
    copied_files: tuple[str, ...]
    removed_files: tuple[str, ...]
    unchanged_files: int


@dataclass(frozen=True)
class LocalFastToolchain:
    env: dict[str, str]
    flutter_cmd: str
    flutter_sdk: Path | None
    sdk_dir: Path | None
    java_home: Path | None


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


def _properties_lines(values: Mapping[str, str]) -> list[str]:
    return [f"{key}={_properties_escape(value)}" for key, value in values.items()]


def _read_active_property_lines(path: Path) -> list[str]:
    if not path.is_file():
        return []
    lines: list[str] = []
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        lines.append(line)
    return lines


def _write_properties(path: Path, values: Mapping[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = _properties_lines(values)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _has_android_36(path: Path) -> bool:
    return (path / "platforms" / "android-36").is_dir()


def _has_flutter_bin(path: Path) -> bool:
    return (path / "bin" / "flutter").exists() or (path / "bin" / "flutter.bat").exists()


def _has_java_bin(path: Path) -> bool:
    exe = "java.exe" if sys.platform == "win32" else "java"
    return (path / "bin" / exe).is_file()


def _is_jdk_17(path: Path) -> bool:
    if not _has_java_bin(path):
        return False
    release_file = path / "release"
    if release_file.is_file():
        text = release_file.read_text(encoding="utf-8", errors="replace")
        if re.search(r'JAVA_VERSION="17\b', text):
            return True
        if "JAVA_VERSION=" in text:
            return False
    return "17" in path.name


def ensure_mirror_local_properties(
    mirror_root: Path,
    *,
    sdk_dir: Path | None,
    flutter_sdk: Path | None,
) -> None:
    """Repair and escape only the mirror copy; the shared worktree is never written."""

    if mirror_root.resolve() == local_app_root().resolve():
        return
    properties_path = mirror_root / "android" / "local.properties"
    if not properties_path.parent.is_dir():
        return
    raw_lines = _read_active_property_lines(properties_path)
    current = _read_properties(properties_path)
    repo_hints = _read_properties(local_app_root() / "android" / "local.properties")

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
    if repo_hints.get("sdk.dir"):
        sdk_candidates.append(Path(repo_hints["sdk.dir"]))
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
    flutter_candidates: list[Path] = []
    if flutter_sdk is not None:
        flutter_candidates.append(flutter_sdk)
    if current_flutter:
        flutter_candidates.append(Path(current_flutter))
    if repo_hints.get("flutter.sdk"):
        flutter_candidates.append(Path(repo_hints["flutter.sdk"]))
    chosen_flutter = next(
        (candidate for candidate in flutter_candidates if _has_flutter_bin(candidate)),
        None,
    )
    if chosen_flutter is not None and (
        not current_flutter
        or not _has_flutter_bin(Path(current_flutter))
        or (
            flutter_sdk is not None
            and Path(current_flutter).resolve() != chosen_flutter.resolve()
        )
    ):
        current["flutter.sdk"] = str(chosen_flutter)
        changed = True

    expected_lines = _properties_lines(current)
    if changed or (current and raw_lines != expected_lines):
        _write_properties(properties_path, current)


def _handle_remove_readonly(func, path: str, _exc_info) -> None:  # noqa: ANN001
    try:
        os.chmod(path, stat.S_IWRITE)
    except OSError:
        pass
    func(path)


def _safe_rmtree(path: Path) -> None:
    if not path.exists():
        return
    target: str | Path = path
    if sys.platform == "win32":
        resolved = str(path.resolve())
        if not resolved.startswith("\\\\?\\"):
            target = "\\\\?\\" + resolved
    if sys.version_info >= (3, 12):
        shutil.rmtree(target, onexc=_handle_remove_readonly)
    else:
        shutil.rmtree(target, onerror=_handle_remove_readonly)


def _is_skipped_mirror_path(rel_parts: tuple[str, ...]) -> bool:
    if not rel_parts:
        return False
    if any(part in MIRROR_SKIP_NAMES for part in rel_parts):
        return True
    if rel_parts[-1].lower().endswith(MIRROR_SKIP_SUFFIXES):
        return True
    for prefix in MIRROR_SKIP_PREFIXES:
        if rel_parts[: len(prefix)] == prefix:
            return True
    return False


def _files_equal(first: Path, second: Path) -> bool:
    chunk_size = 65536
    with first.open("rb") as left, second.open("rb") as right:
        while True:
            left_chunk = left.read(chunk_size)
            right_chunk = right.read(chunk_size)
            if left_chunk != right_chunk:
                return False
            if not left_chunk:
                return True


def sync_mirror_incremental(
    source: Path,
    destination: Path,
    *,
    clean: bool = False,
) -> SyncReport:
    """Incrementally mirror source -> destination while preserving Gradle/Flutter caches."""

    if clean and destination.exists():
        _safe_rmtree(destination)
    destination.mkdir(parents=True, exist_ok=True)

    expected_files: set[str] = set()
    expected_dirs: set[str] = set()
    copied: list[str] = []
    unchanged = 0

    for root, dirnames, filenames in os.walk(source, topdown=True):
        root_path = Path(root)
        rel_root = root_path.relative_to(source)
        rel_root_parts = rel_root.parts
        if rel_root_parts:
            expected_dirs.add("/".join(rel_root_parts))

        kept_dirs: list[str] = []
        for dirname in dirnames:
            child_parts = (*rel_root_parts, dirname)
            if not _is_skipped_mirror_path(child_parts):
                kept_dirs.append(dirname)
        dirnames[:] = kept_dirs

        for filename in filenames:
            rel_parts = (*rel_root_parts, filename)
            if _is_skipped_mirror_path(rel_parts):
                continue
            rel_posix = "/".join(rel_parts)
            expected_files.add(rel_posix)
            src_file = root_path / filename
            dst_file = destination.joinpath(*rel_parts)
            if dst_file.is_file():
                src_stat = src_file.stat()
                dst_stat = dst_file.stat()
                if src_stat.st_size == dst_stat.st_size and (
                    src_stat.st_mtime_ns == dst_stat.st_mtime_ns
                    or _files_equal(src_file, dst_file)
                ):
                    unchanged += 1
                    continue
            dst_file.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src_file, dst_file)
            copied.append(rel_posix)

    removed: list[str] = []
    for root, dirnames, filenames in os.walk(destination, topdown=True):
        root_path = Path(root)
        rel_root_parts = root_path.relative_to(destination).parts
        kept_dirs = []
        for dirname in dirnames:
            child_parts = (*rel_root_parts, dirname)
            if not _is_skipped_mirror_path(child_parts):
                kept_dirs.append(dirname)
        dirnames[:] = kept_dirs

        for filename in filenames:
            rel_parts = (*rel_root_parts, filename)
            if _is_skipped_mirror_path(rel_parts):
                continue
            rel_posix = "/".join(rel_parts)
            if rel_posix not in expected_files:
                (root_path / filename).unlink(missing_ok=True)
                removed.append(rel_posix)

    for root, dirnames, _filenames in os.walk(destination, topdown=False):
        root_path = Path(root)
        if root_path == destination:
            continue
        rel_parts = root_path.relative_to(destination).parts
        if _is_skipped_mirror_path(rel_parts):
            continue
        if "/".join(rel_parts) not in expected_dirs:
            try:
                if not any(root_path.iterdir()):
                    root_path.rmdir()
            except OSError:
                pass

    return SyncReport(
        copied_files=tuple(sorted(copied)),
        removed_files=tuple(sorted(removed)),
        unchanged_files=unchanged,
    )


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
        _safe_rmtree(destination)
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


def _gradle_command(
    app_root: Path,
    tasks: Sequence[str] = (":app:assembleDebug", ":app:assembleDebugAndroidTest"),
    *,
    use_daemon: bool = False,
) -> list[str]:
    if sys.platform == "win32":
        cmd = ["cmd", "/c", str(app_root / "android" / "gradlew.bat"), *tasks]
    else:
        cmd = [str(app_root / "android" / "gradlew"), *tasks]
    if not use_daemon:
        cmd.append("--no-daemon")
    return cmd


def _resolve_local_fast_toolchain(
    *,
    sdk_dir: Path | None = None,
    flutter_sdk: Path | None = None,
    java_home: Path | None = None,
) -> LocalFastToolchain:
    env = os.environ.copy()
    repo_hints = _read_properties(local_app_root() / "android" / "local.properties")

    # 1. Flutter SDK & executable
    flutter_candidates: list[Path] = []
    if flutter_sdk is not None:
        flutter_candidates.append(flutter_sdk)
    if env.get("FLUTTER_ROOT"):
        flutter_candidates.append(Path(env["FLUTTER_ROOT"]))
    for tool_name in ("flutter.bat", "flutter"):
        found = shutil.which(tool_name)
        if found:
            flutter_candidates.append(Path(found).resolve().parents[1])
    if repo_hints.get("flutter.sdk"):
        flutter_candidates.append(Path(repo_hints["flutter.sdk"]))
    flutter_candidates.append(Path("D:/campus-tools/flutter"))
    chosen_flutter = next(
        (candidate for candidate in flutter_candidates if _has_flutter_bin(candidate)),
        None,
    )
    if chosen_flutter is not None:
        bin_name = "flutter.bat" if sys.platform == "win32" else "flutter"
        candidate_bin = chosen_flutter / "bin" / bin_name
        flutter_cmd = (
            str(candidate_bin)
            if candidate_bin.is_file()
            else str(chosen_flutter / "bin" / "flutter")
        )
    else:
        flutter_cmd = shutil.which("flutter.bat") or shutil.which("flutter") or "flutter"

    # 2. Android SDK (requires platforms/android-36)
    sdk_candidates: list[Path] = []
    if sdk_dir is not None:
        sdk_candidates.append(sdk_dir)
    for key in ("ANDROID_SDK_ROOT", "ANDROID_HOME"):
        if env.get(key):
            sdk_candidates.append(Path(env[key]))
    if repo_hints.get("sdk.dir"):
        sdk_candidates.append(Path(repo_hints["sdk.dir"]))
    sdk_candidates.append(Path("D:/campus-tools/android"))
    sdk_candidates.append(Path.home() / "AppData" / "Local" / "Android" / "Sdk")
    chosen_sdk = next(
        (candidate for candidate in sdk_candidates if _has_android_36(candidate)),
        None,
    )
    if chosen_sdk is not None:
        env["ANDROID_HOME"] = str(chosen_sdk)
        env["ANDROID_SDK_ROOT"] = str(chosen_sdk)

    # 3. JDK 17 (prefer explicit --java-home, else env JAVA_HOME if JDK 17, else probe sibling jdk17*)
    chosen_java: Path | None = None
    if java_home is not None:
        if not _has_java_bin(java_home):
            raise ManifestError(f"--java-home does not contain bin/java: {java_home}")
        chosen_java = java_home
    else:
        env_java = Path(env["JAVA_HOME"]) if env.get("JAVA_HOME") else None
        if env_java is not None and _is_jdk_17(env_java):
            chosen_java = env_java
        else:
            jdk_roots: list[Path] = []
            for anchor in (chosen_sdk, chosen_flutter):
                if anchor is not None and anchor.parent.is_dir():
                    jdk_roots.append(anchor.parent)
            campus_tools = Path("D:/campus-tools")
            if campus_tools.is_dir() and campus_tools not in jdk_roots:
                jdk_roots.append(campus_tools)
            jdk_candidates: list[Path] = []
            for root in jdk_roots:
                for pattern in ("jdk17*", "jdk-17*"):
                    jdk_candidates.extend(sorted(root.glob(pattern)))
            chosen_java = next(
                (candidate for candidate in jdk_candidates if _is_jdk_17(candidate)),
                None,
            )
    if chosen_java is not None:
        env["JAVA_HOME"] = str(chosen_java)
        java_bin = str(chosen_java / "bin")
        existing_path = env.get("PATH", "")
        if java_bin not in existing_path.split(os.pathsep):
            env["PATH"] = f"{java_bin}{os.pathsep}{existing_path}" if existing_path else java_bin

    return LocalFastToolchain(
        env=env,
        flutter_cmd=flutter_cmd,
        flutter_sdk=chosen_flutter,
        sdk_dir=chosen_sdk,
        java_home=chosen_java,
    )


def _run_streaming(
    cmd: list[str],
    *,
    cwd: Path,
    env: Mapping[str, str] | None = None,
) -> int:
    print("+ " + " ".join(str(part) for part in cmd), flush=True)
    completed = subprocess.run(cmd, cwd=cwd, env=env)
    return completed.returncode


def _default_local_fast_dir() -> Path:
    drive_d = Path("D:/")
    if drive_d.exists():
        return Path("D:/campus-tools/build-work/cx-android-cache")
    return Path(tempfile.gettempdir()) / "cx-android-cache"


def run_local_fast(
    *,
    cache_dir: Path | None = None,
    tasks: Sequence[str] | None = None,
    sdk_dir: Path | None = None,
    flutter_sdk: Path | None = None,
    java_home: Path | None = None,
    clean_cache: bool = False,
    force_pub_get: bool = False,
    use_daemon: bool = False,
    dry_run: bool = False,
) -> int:
    """Incrementally sync to persistent ASCII cache and run local Gradle checks."""

    selected_tasks = tuple(tasks) if tasks else LOCAL_FAST_TASKS
    target_cache = cache_dir or _default_local_fast_dir()
    if not str(target_cache).isascii():
        raise ManifestError(f"--cache-dir must be ASCII: {target_cache}")
    mirror_root = target_cache / "local_app"
    toolchain = _resolve_local_fast_toolchain(
        sdk_dir=sdk_dir,
        flutter_sdk=flutter_sdk,
        java_home=java_home,
    )
    gradle_cmd = _gradle_command(
        mirror_root,
        tasks=selected_tasks,
        use_daemon=use_daemon,
    )

    if dry_run:
        print(f"[DRY-RUN] local-fast cache: {mirror_root}")
        print(f"[DRY-RUN] JAVA_HOME={toolchain.java_home or toolchain.env.get('JAVA_HOME', '')}")
        print(f"[DRY-RUN] ANDROID_SDK_ROOT={toolchain.sdk_dir or toolchain.env.get('ANDROID_SDK_ROOT', '')}")
        print(f"[DRY-RUN] FLUTTER_SDK={toolchain.flutter_sdk or ''}")
        print(f"+ {toolchain.flutter_cmd} --no-version-check pub get --offline (if needed)")
        print("+ " + " ".join(gradle_cmd))
        return 0

    started_total = time.monotonic()
    sync_started = time.monotonic()
    report = sync_mirror_incremental(
        local_app_root(),
        mirror_root,
        clean=clean_cache,
    )
    print(
        f"[SYNC] {mirror_root} "
        f"(copied={len(report.copied_files)}, removed={len(report.removed_files)}, "
        f"unchanged={report.unchanged_files}, {time.monotonic() - sync_started:.1f}s)",
        flush=True,
    )

    package_config = mirror_root / ".dart_tool" / "package_config.json"
    local_props = mirror_root / "android" / "local.properties"
    needs_pub_get = (
        force_pub_get
        or clean_cache
        or not package_config.is_file()
        or not local_props.is_file()
        or "pubspec.yaml" in report.copied_files
        or "pubspec.lock" in report.copied_files
    )
    if needs_pub_get:
        ensure_mirror_local_properties(
            mirror_root,
            sdk_dir=toolchain.sdk_dir,
            flutter_sdk=toolchain.flutter_sdk,
        )
        pub_started = time.monotonic()
        pub_code = _run_streaming(
            [toolchain.flutter_cmd, "--no-version-check", "pub", "get", "--offline"],
            cwd=mirror_root,
            env=toolchain.env,
        )
        if pub_code != 0:
            print(f"[FAIL] flutter pub get --offline failed (exit={pub_code}).", file=sys.stderr)
            return 1
        print(f"[PASS] flutter pub get --offline ({time.monotonic() - pub_started:.1f}s)", flush=True)
    else:
        print("[SKIP] flutter pub get --offline (pubspec & package_config unchanged)", flush=True)

    # Always normalize and escape local.properties AFTER pub get to prevent [PropertyEscape] lint failures.
    ensure_mirror_local_properties(
        mirror_root,
        sdk_dir=toolchain.sdk_dir,
        flutter_sdk=toolchain.flutter_sdk,
    )

    gradle_started = time.monotonic()
    gradle_code = _run_streaming(
        gradle_cmd,
        cwd=mirror_root / "android",
        env=toolchain.env,
    )
    if gradle_code != 0:
        print(
            f"[FAIL] Local Android fast check failed (exit={gradle_code}, "
            f"{time.monotonic() - gradle_started:.1f}s).",
            file=sys.stderr,
        )
        return 1
    print(
        f"[PASS] Local Android fast check ({' '.join(selected_tasks)}) "
        f"succeeded (gradle={time.monotonic() - gradle_started:.1f}s, "
        f"total={time.monotonic() - started_total:.1f}s).",
        flush=True,
    )
    return 0


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
    parser.add_argument(
        "--local-fast",
        action="store_true",
        help=(
            "Incrementally mirror local_app to a persistent ASCII cache, repair "
            "local.properties escaping, and run unit tests + androidTest compile + lint "
            "without needing a device."
        ),
    )
    parser.add_argument("--cache-dir", type=Path)
    parser.add_argument("--gradle-tasks", nargs="+")
    parser.add_argument("--clean-cache", action="store_true")
    parser.add_argument("--force-pub-get", action="store_true")
    parser.add_argument("--use-daemon", action="store_true")
    parser.add_argument("--java-home", type=Path)
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
        if args.local_fast:
            if args.oem_readonly_audit or args.doze_probe or args.allow_wipe_physical or args.serial:
                print(
                    "[FAIL] --local-fast runs host Gradle checks only and cannot be "
                    "combined with --serial, --oem-readonly-audit, --doze-probe, or "
                    "--allow-wipe-physical.",
                    file=sys.stderr,
                )
                return 2
            return run_local_fast(
                cache_dir=args.cache_dir or args.work_dir,
                tasks=args.gradle_tasks,
                sdk_dir=args.sdk_dir,
                flutter_sdk=args.flutter_sdk,
                java_home=args.java_home,
                clean_cache=args.clean_cache,
                force_pub_get=args.force_pub_get,
                use_daemon=args.use_daemon,
                dry_run=args.dry_run,
            )

        serials = normalize_serials(args.serial)
        if not serials:
            print(
                "[FAIL] --serial is required unless --verify-manifest-only or --local-fast is used.",
                file=sys.stderr,
            )
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
