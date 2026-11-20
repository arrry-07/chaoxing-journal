#!/usr/bin/env python3
"""One-command APK release verifier and Markdown acceptance snippet generator.

Checks:
  1. File size and SHA-256 digest (optional SHA256SUMS.txt read/write)
  2. Full ZIP entry CRC-32 integrity and entry count
  3. Exact ABI set and libflutter.so presence per ABI
  4. Package name, versionName/versionCode, minSdk/targetSdk, non-debuggable (via aapt2/aapt)
  5. 16 KiB page alignment (via zipalign -c -P 16 4)
  6. APK Signature Scheme v2 verification and signer SHA-256 fingerprint (via apksigner)

Prints a ready-to-paste Markdown acceptance section matching docs/reviews/ style.
"""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass, field
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import zipfile


DEFAULT_PACKAGE = "com.example.studyassistant.journal"
DEFAULT_ABIS = ("arm64-v8a", "x86_64")
DEFAULT_SIGNER_SHA256 = (
    "d36a571510e046dd196d7384f849f82b4fcff05ce3affb334765d5c752265d8a"
)
DEFAULT_MIN_SDK = 26
DEFAULT_TARGET_SDK = 36


@dataclass
class VerificationReport:
    apk_path: str
    apk_name: str
    size_bytes: int
    sha256: str
    zip_entries: int
    zip_crc_ok: bool
    abis: list[str]
    abi_ok: bool
    package_name: str | None = None
    version_name: str | None = None
    version_code: int | None = None
    min_sdk: int | None = None
    target_sdk: int | None = None
    debuggable: bool | None = None
    zipalign_16k_ok: bool = False
    v2_signed: bool = False
    signer_sha256: str | None = None
    signer_match: bool = False
    sha256sums_ok: bool | None = None
    source_commit: str | None = None
    build_tools_dir: str | None = None
    errors: list[str] = field(default_factory=list)

    @property
    def passed(self) -> bool:
        return not self.errors


def _version_sort_key(path: Path) -> tuple[int, ...]:
    parts = re.findall(r"\d+", path.name)
    return tuple(int(p) for p in parts) if parts else (0,)


def _read_sdk_dir_from_local_properties(repo_root: Path) -> Path | None:
    props = repo_root / "study_assistant-1.1.0" / "local_app" / "android" / "local.properties"
    if not props.is_file():
        return None
    for line in props.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if line.startswith("sdk.dir="):
            raw = line.split("=", 1)[1].strip()
            # Unescape Java properties path escapes such as C\:\\Android\\Sdk or C:\\rea-tools\\android
            raw = raw.replace(r"\:", ":").replace(r"\\", "\\")
            candidate = Path(raw)
            if candidate.is_dir():
                return candidate
    return None


def discover_build_tools_dir(
    explicit_dir: Path | None = None,
    repo_root: Path | None = None,
) -> Path | None:
    if explicit_dir is not None:
        return explicit_dir if explicit_dir.is_dir() else None

    sdk_roots: list[Path] = []
    for env_key in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        val = os.environ.get(env_key)
        if val:
            sdk_roots.append(Path(val))

    if repo_root is not None:
        props_sdk = _read_sdk_dir_from_local_properties(repo_root)
        if props_sdk is not None:
            sdk_roots.append(props_sdk)

    local_app_data = os.environ.get("LOCALAPPDATA")
    if local_app_data:
        sdk_roots.append(Path(local_app_data) / "Android" / "Sdk")

    sdk_roots.extend(
        [
            Path(r"D:\campus-tools\android"),
            Path.home() / "Android" / "Sdk",
            Path.home() / "Library" / "Android" / "sdk",
        ]
    )

    candidates: list[Path] = []
    seen: set[Path] = set()
    for sdk_root in sdk_roots:
        bt_root = sdk_root / "build-tools"
        if not bt_root.is_dir():
            continue
        for child in bt_root.iterdir():
            if child.is_dir():
                resolved = child.resolve()
                if resolved not in seen:
                    seen.add(resolved)
                    candidates.append(resolved)

    if not candidates:
        return None

    candidates.sort(key=_version_sort_key, reverse=True)
    for cand in candidates:
        if _find_tool_in_dir(cand, "apksigner") and _find_tool_in_dir(cand, "zipalign"):
            return cand
    return candidates[0]


def _find_tool_in_dir(directory: Path | None, name: str) -> str | None:
    if directory is None:
        return None
    exts = (".exe", ".bat", ".cmd", "") if os.name == "nt" else ("",)
    for ext in exts:
        candidate = directory / f"{name}{ext}"
        if candidate.is_file():
            return str(candidate)
    return None


def resolve_tool(build_tools_dir: Path | None, *names: str) -> str | None:
    for name in names:
        found = _find_tool_in_dir(build_tools_dir, name)
        if found:
            return found
    for name in names:
        found = shutil.which(name)
        if found:
            return found
    return None


def _run_cmd(args: list[str]) -> subprocess.CompletedProcess[str]:
    if os.name == "nt" and args[0].lower().endswith((".bat", ".cmd")):
        cmd = ["cmd.exe", "/c", *args]
    else:
        cmd = args
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )


def compute_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def inspect_zip_and_abis(
    apk_path: Path, expected_abis: list[str]
) -> tuple[int, bool, list[str], list[str]]:
    errors: list[str] = []
    with zipfile.ZipFile(apk_path, "r") as archive:
        names = archive.namelist()
        bad_entry = archive.testzip()
        crc_ok = bad_entry is None
        if not crc_ok:
            errors.append(f"ZIP CRC check failed at entry: {bad_entry}")

        native_entries = [
            name for name in names if name.startswith("lib/") and name.endswith(".so")
        ]

    observed = sorted(
        {
            name.split("/", 2)[1]
            for name in native_entries
            if len(name.split("/", 2)) == 3
        }
    )
    expected_set = set(expected_abis)
    unexpected = sorted(set(observed) - expected_set)
    if unexpected:
        errors.append(f"unexpected ABI directories: {', '.join(unexpected)}")
    for abi in sorted(expected_set):
        engine = f"lib/{abi}/libflutter.so"
        if engine not in native_entries:
            errors.append(f"missing Flutter engine in ABI {abi}: {engine}")

    return len(names), crc_ok, observed, errors


def parse_badging_output(output: str) -> dict[str, object]:
    result: dict[str, object] = {
        "package_name": None,
        "version_code": None,
        "version_name": None,
        "min_sdk": None,
        "target_sdk": None,
        "debuggable": False,
    }
    pkg_match = re.search(
        r"package:\s+name='([^']+)'\s+versionCode='(\d+)'\s+versionName='([^']+)'",
        output,
    )
    if pkg_match:
        result["package_name"] = pkg_match.group(1)
        result["version_code"] = int(pkg_match.group(2))
        result["version_name"] = pkg_match.group(3)

    min_match = re.search(r"^(?:minS|s)dkVersion:'(\d+)'", output, re.M)
    if min_match:
        result["min_sdk"] = int(min_match.group(1))

    target_match = re.search(r"^targetSdkVersion:'(\d+)'", output, re.M)
    if target_match:
        result["target_sdk"] = int(target_match.group(1))

    if re.search(r"^application-debuggable\b", output, re.M):
        result["debuggable"] = True

    return result


def parse_apksigner_output(output: str) -> tuple[bool, str | None]:
    v2_match = re.search(
        r"Verified using v2 scheme \(APK Signature Scheme v2\):\s*true",
        output,
        re.I,
    )
    cert_match = re.search(
        r"Signer #1 certificate SHA-256 digest:\s*([0-9a-fA-F]{64})",
        output,
    )
    return bool(v2_match), cert_match.group(1).lower() if cert_match else None


def parse_expected_version(raw: str | None) -> tuple[str | None, int | None]:
    if not raw:
        return None, None
    if "+" in raw:
        name, code_str = raw.split("+", 1)
        return name.strip(), int(code_str.strip())
    return raw.strip(), None


def verify_sha256sums_file(sums_path: Path, apk_name: str, actual_sha256: str) -> list[str]:
    if not sums_path.is_file():
        return [f"SHA256SUMS file not found: {sums_path}"]
    for line in sums_path.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        parts = re.split(r"\s+", stripped, maxsplit=1)
        if len(parts) != 2:
            continue
        digest, fname = parts[0].lower(), parts[1].lstrip("*").strip()
        if Path(fname).name == apk_name:
            if digest == actual_sha256.lower():
                return []
            return [
                f"SHA256SUMS mismatch for {apk_name}: expected {digest}, actual {actual_sha256}"
            ]
    return [f"SHA256SUMS has no entry for {apk_name}: {sums_path}"]


def verify_apk(
    apk_path: Path,
    *,
    expected_package: str = DEFAULT_PACKAGE,
    expected_version: str | None = None,
    expected_abis: list[str] | None = None,
    expected_signer: str = DEFAULT_SIGNER_SHA256,
    expected_min_sdk: int = DEFAULT_MIN_SDK,
    expected_target_sdk: int = DEFAULT_TARGET_SDK,
    build_tools_dir: Path | None = None,
    sha256sums_path: Path | None = None,
    source_commit: str | None = None,
    repo_root: Path | None = None,
) -> VerificationReport:
    if not apk_path.is_file():
        raise FileNotFoundError(f"APK not found: {apk_path}")

    abis = expected_abis if expected_abis else list(DEFAULT_ABIS)
    size_bytes = apk_path.stat().st_size
    sha256 = compute_sha256(apk_path)
    zip_entries, zip_crc_ok, observed_abis, zip_errors = inspect_zip_and_abis(
        apk_path, abis
    )

    resolved_bt = discover_build_tools_dir(build_tools_dir, repo_root=repo_root)
    report = VerificationReport(
        apk_path=str(apk_path.resolve()),
        apk_name=apk_path.name,
        size_bytes=size_bytes,
        sha256=sha256,
        zip_entries=zip_entries,
        zip_crc_ok=zip_crc_ok,
        abis=observed_abis,
        abi_ok=not any("ABI" in e or "libflutter.so" in e for e in zip_errors),
        source_commit=source_commit,
        build_tools_dir=str(resolved_bt) if resolved_bt else None,
        errors=list(zip_errors),
    )

    # 1. aapt2 / aapt badging
    aapt_tool = resolve_tool(resolved_bt, "aapt2", "aapt")
    if not aapt_tool:
        report.errors.append("aapt2/aapt not found (pass --build-tools-dir or set ANDROID_HOME)")
    else:
        proc = _run_cmd([aapt_tool, "dump", "badging", str(apk_path)])
        if proc.returncode != 0:
            report.errors.append(f"aapt dump badging failed: {proc.stderr.strip() or proc.stdout.strip()}")
        else:
            parsed = parse_badging_output(proc.stdout)
            report.package_name = parsed["package_name"]  # type: ignore[assignment]
            report.version_name = parsed["version_name"]  # type: ignore[assignment]
            report.version_code = parsed["version_code"]  # type: ignore[assignment]
            report.min_sdk = parsed["min_sdk"]  # type: ignore[assignment]
            report.target_sdk = parsed["target_sdk"]  # type: ignore[assignment]
            report.debuggable = bool(parsed["debuggable"])

            if expected_package and report.package_name != expected_package:
                report.errors.append(
                    f"package mismatch: expected {expected_package}, got {report.package_name}"
                )
            exp_vname, exp_vcode = parse_expected_version(expected_version)
            if exp_vname and report.version_name != exp_vname:
                report.errors.append(
                    f"versionName mismatch: expected {exp_vname}, got {report.version_name}"
                )
            if exp_vcode is not None and report.version_code != exp_vcode:
                report.errors.append(
                    f"versionCode mismatch: expected {exp_vcode}, got {report.version_code}"
                )
            if expected_min_sdk and report.min_sdk != expected_min_sdk:
                report.errors.append(
                    f"minSdk mismatch: expected {expected_min_sdk}, got {report.min_sdk}"
                )
            if expected_target_sdk and report.target_sdk != expected_target_sdk:
                report.errors.append(
                    f"targetSdk mismatch: expected {expected_target_sdk}, got {report.target_sdk}"
                )
            if report.debuggable:
                report.errors.append("APK is debuggable (expected release non-debuggable)")

    # 2. zipalign 16 KiB alignment
    zipalign_tool = resolve_tool(resolved_bt, "zipalign")
    if not zipalign_tool:
        report.errors.append("zipalign not found (pass --build-tools-dir or set ANDROID_HOME)")
    else:
        proc = _run_cmd([zipalign_tool, "-c", "-P", "16", "4", str(apk_path)])
        report.zipalign_16k_ok = proc.returncode == 0
        if not report.zipalign_16k_ok:
            report.errors.append(
                f"zipalign -c -P 16 4 failed: {proc.stderr.strip() or proc.stdout.strip()}"
            )

    # 3. apksigner v2 & signer fingerprint
    apksigner_tool = resolve_tool(resolved_bt, "apksigner")
    if not apksigner_tool:
        report.errors.append("apksigner not found (pass --build-tools-dir or set ANDROID_HOME)")
    else:
        proc = _run_cmd(
            [apksigner_tool, "verify", "--verbose", "--print-certs", str(apk_path)]
        )
        combined = f"{proc.stdout}\n{proc.stderr}"
        v2_ok, signer_sha = parse_apksigner_output(combined)
        report.v2_signed = proc.returncode == 0 and v2_ok
        report.signer_sha256 = signer_sha
        if proc.returncode != 0:
            report.errors.append(f"apksigner verify failed: {proc.stderr.strip() or proc.stdout.strip()}")
        if not v2_ok:
            report.errors.append("APK Signature Scheme v2 not verified")
        if expected_signer:
            report.signer_match = signer_sha == expected_signer.lower()
            if not report.signer_match:
                report.errors.append(
                    f"signer SHA-256 mismatch: expected {expected_signer.lower()}, got {signer_sha}"
                )
        else:
            report.signer_match = bool(signer_sha)

    # 4. Optional SHA256SUMS.txt verification
    if sha256sums_path is not None:
        sums_errors = verify_sha256sums_file(sha256sums_path, apk_path.name, sha256)
        report.sha256sums_ok = not sums_errors
        report.errors.extend(sums_errors)

    return report


def format_markdown_report(report: VerificationReport) -> str:
    abi_label = "/".join(
        "ARM64" if a == "arm64-v8a" else a for a in report.abis
    ) or "未知"
    debug_label = "非 debuggable" if report.debuggable is False else "debuggable（异常）"
    signer_short = (
        f"`{report.signer_sha256[:8]}...`" if report.signer_sha256 else "未检出"
    )
    align_label = "通过" if report.zipalign_16k_ok else "失败"
    crc_label = "通过" if report.zip_crc_ok else "失败"
    status_label = "全部通过" if report.passed else f"存在 {len(report.errors)} 项阻断"

    lines = ["## 正式包校验结果", ""]
    if report.source_commit:
        lines.append(
            f"- 从干净源码 `{report.source_commit}` 导出到 ASCII 目录构建，正常 `lib/main.dart`、锁定依赖、原体验证书。"
        )
    lines.append(
        f"- 文件：`{report.apk_name}`，`{report.size_bytes:,}` 字节，SHA-256 `{report.sha256}`。"
    )
    lines.append(
        f"- 包名 `{report.package_name or '未知'}`，`versionCode {report.version_code} / versionName {report.version_name}`，"
        f"min{report.min_sdk}/target{report.target_sdk}，{abi_label}，{debug_label}；"
        f"v2 证书 {signer_short}；`zipalign -c -P 16 4` {align_label}；ZIP `{report.zip_entries}` 条目 CRC {crc_label}。"
    )
    if report.sha256sums_ok is True:
        lines.append("- `SHA256SUMS.txt` 核对一致。")
    elif report.sha256sums_ok is False:
        lines.append("- `SHA256SUMS.txt` 核对失败（见阻断项）。")
    lines.append(f"- 校验结论：{status_label}。")
    if report.errors:
        lines.append("- 阻断项：")
        for err in report.errors:
            lines.append(f"  - {err}")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Verify release APK (size, SHA-256, ABI, ZIP CRC, badging, 16 KiB zipalign, v2 cert) and print Markdown acceptance snippet."
    )
    parser.add_argument("apk", type=Path, help="Path to the APK file")
    parser.add_argument(
        "--expected-version",
        help="Expected versionName or versionName+versionCode (e.g. 1.8.19+86)",
    )
    parser.add_argument(
        "--expected-package",
        default=DEFAULT_PACKAGE,
        help=f"Expected Android applicationId (default: {DEFAULT_PACKAGE})",
    )
    parser.add_argument(
        "--expected-signer",
        default=DEFAULT_SIGNER_SHA256,
        help="Expected Signer #1 certificate SHA-256 digest (64 hex chars)",
    )
    parser.add_argument(
        "--expected-min-sdk",
        type=int,
        default=DEFAULT_MIN_SDK,
        help=f"Expected minSdkVersion (default: {DEFAULT_MIN_SDK})",
    )
    parser.add_argument(
        "--expected-target-sdk",
        type=int,
        default=DEFAULT_TARGET_SDK,
        help=f"Expected targetSdkVersion (default: {DEFAULT_TARGET_SDK})",
    )
    parser.add_argument(
        "--abi",
        action="append",
        dest="abis",
        help="Expected ABI; repeat for multiple (default: arm64-v8a and x86_64)",
    )
    parser.add_argument(
        "--build-tools-dir",
        type=Path,
        help="Explicit Android SDK build-tools directory (auto-discovered if omitted)",
    )
    parser.add_argument(
        "--source-commit",
        help="Optional git commit hash to include in the Markdown snippet",
    )
    parser.add_argument(
        "--sha256sums",
        type=Path,
        help="Optional existing SHA256SUMS.txt to verify against",
    )
    parser.add_argument(
        "--write-sha256sums",
        nargs="?",
        const="__AUTO__",
        help="Write SHA256SUMS.txt next to the APK (or to the given path)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output machine-readable JSON instead of Markdown",
    )
    args = parser.parse_args(argv)

    repo_root = Path(__file__).resolve().parents[1]
    report = verify_apk(
        args.apk,
        expected_package=args.expected_package,
        expected_version=args.expected_version,
        expected_abis=args.abis,
        expected_signer=args.expected_signer,
        expected_min_sdk=args.expected_min_sdk,
        expected_target_sdk=args.expected_target_sdk,
        build_tools_dir=args.build_tools_dir,
        sha256sums_path=args.sha256sums,
        source_commit=args.source_commit,
        repo_root=repo_root,
    )

    if args.write_sha256sums and report.passed:
        out_sums = (
            args.apk.parent / "SHA256SUMS.txt"
            if args.write_sha256sums == "__AUTO__"
            else Path(args.write_sha256sums)
        )
        out_sums.write_text(
            f"{report.sha256}  {report.apk_name}\n",
            encoding="utf-8",
            newline="\n",
        )
        report.sha256sums_ok = True

    if args.json:
        payload = asdict(report)
        payload["passed"] = report.passed
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        print(format_markdown_report(report))

    if not report.passed:
        for err in report.errors:
            print(f"ERROR: {err}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
