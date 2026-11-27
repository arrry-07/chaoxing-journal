#!/usr/bin/env python3
"""Unified local verification gate matching repository AGENTS & VALIDATION rules."""

from __future__ import annotations

import argparse
import codecs
from collections import deque
from collections.abc import Sequence
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import threading
import time

DEFAULT_TEST_CASE_TIMEOUT = "30s"
DEFAULT_QUICK_FLUTTER_TIMEOUT_SECONDS = 300
DEFAULT_FULL_FLUTTER_TIMEOUT_SECONDS = 900
_FLUTTER_PROGRESS_RE = re.compile(r"^\d+:\d{2}(?::\d{2})?\s+[+\-~]")
_ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")


def _resolve_tool(*names: str) -> str:
    for name in names:
        found = shutil.which(name)
        if found:
            return found
    raise FileNotFoundError(f"Tool not found in PATH: {', '.join(names)}")


def _run_step(label: str, cmd: list[str], cwd: Path) -> None:
    print(f"==> {label}")
    proc = subprocess.run(cmd, cwd=cwd)
    if proc.returncode != 0:
        raise RuntimeError(f"[FAIL] {label} (exit={proc.returncode})")
    print(f"[PASS] {label}")


def _build_flutter_test_cmd(
    flutter_cmd: str,
    tests: Sequence[str],
    *,
    test_case_timeout: str | None = DEFAULT_TEST_CASE_TIMEOUT,
) -> list[str]:
    cmd = [flutter_cmd, "--no-version-check", "test", "--no-pub"]
    normalized = (test_case_timeout or "").strip()
    if normalized:
        cmd.extend(
            [
                "--timeout",
                "none" if normalized.lower() == "none" else normalized,
            ]
        )
    if tests:
        cmd.extend(tests)
    return cmd


def _terminate_process_tree(proc: subprocess.Popen[bytes] | subprocess.Popen[str]) -> None:
    if proc.poll() is not None:
        return
    if sys.platform == "win32":
        subprocess.run(
            ["taskkill", "/F", "/T", "/PID", str(proc.pid)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    else:
        try:
            os.killpg(proc.pid, 9)
        except OSError:
            pass
    try:
        proc.kill()
    except OSError:
        pass
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        pass


def _run_flutter_step(
    label: str,
    cmd: list[str],
    cwd: Path,
    *,
    timeout_seconds: int | None,
) -> None:
    suffix = f" (hard timeout: {timeout_seconds}s)" if timeout_seconds and timeout_seconds > 0 else ""
    print(f"==> {label}{suffix}", flush=True)
    started = time.monotonic()
    popen_kwargs: dict[str, object] = {
        "cwd": cwd,
        "stdout": subprocess.PIPE,
        "stderr": subprocess.STDOUT,
    }
    if sys.platform != "win32":
        popen_kwargs["start_new_session"] = True
    proc = subprocess.Popen(cmd, **popen_kwargs)

    state_lock = threading.Lock()
    recent_lines: deque[str] = deque(maxlen=10)
    last_test_line: str | None = None
    partial_line = ""

    def _record_segment(segment: str) -> None:
        nonlocal last_test_line
        cleaned = _ANSI_ESCAPE_RE.sub("", segment).strip()
        if not cleaned:
            return
        with state_lock:
            recent_lines.append(cleaned)
            if _FLUTTER_PROGRESS_RE.match(cleaned):
                last_test_line = cleaned

    def _drain_output() -> None:
        nonlocal partial_line
        if proc.stdout is None:
            return
        decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")
        fd = proc.stdout.fileno()
        buffer = ""
        try:
            while True:
                chunk = os.read(fd, 4096)
                if not chunk:
                    tail = decoder.decode(b"", final=True)
                    if tail:
                        sys.stdout.write(tail)
                        sys.stdout.flush()
                        buffer += tail
                    break
                text = decoder.decode(chunk, final=False)
                if not text:
                    continue
                sys.stdout.write(text)
                sys.stdout.flush()
                buffer += text
                parts = re.split(r"[\r\n]+", buffer)
                if buffer.endswith(("\r", "\n")):
                    for seg in parts:
                        _record_segment(seg)
                    buffer = ""
                else:
                    for seg in parts[:-1]:
                        _record_segment(seg)
                    buffer = parts[-1]
                with state_lock:
                    partial_line = _ANSI_ESCAPE_RE.sub("", buffer).strip()
            if buffer:
                _record_segment(buffer)
                with state_lock:
                    partial_line = ""
        except (OSError, ValueError):
            pass

    reader = threading.Thread(target=_drain_output, daemon=True)
    reader.start()
    effective_timeout = timeout_seconds if timeout_seconds and timeout_seconds > 0 else None
    try:
        returncode = proc.wait(timeout=effective_timeout)
    except subprocess.TimeoutExpired:
        _terminate_process_tree(proc)
        reader.join(timeout=2)
        with state_lock:
            candidate_partial = (
                partial_line
                if partial_line and _FLUTTER_PROGRESS_RE.match(partial_line)
                else None
            )
            last_seen = (
                candidate_partial
                or last_test_line
                or partial_line
                or (recent_lines[-1] if recent_lines else "<no output captured>")
            )
        raise RuntimeError(
            f"[FAIL] {label} (timed out after {effective_timeout}s; "
            f"last output: {last_seen})"
        ) from None
    except BaseException:
        _terminate_process_tree(proc)
        raise
    finally:
        if proc.poll() is None:
            _terminate_process_tree(proc)
        reader.join(timeout=2)
        if proc.stdout is not None and not reader.is_alive():
            try:
                proc.stdout.close()
            except (OSError, ValueError):
                pass
    elapsed = time.monotonic() - started
    if returncode != 0:
        raise RuntimeError(f"[FAIL] {label} (exit={returncode}, elapsed={elapsed:.1f}s)")
    print(f"[PASS] {label} ({elapsed:.1f}s)")


def _changed_dart_files(repo: Path, app_dir: Path, base: str | None = None) -> list[str]:
    paths: set[str] = set()
    if base is None:
        common = subprocess.run(
            ["git", "merge-base", "refs/remotes/origin/main", "HEAD"],
            cwd=repo, capture_output=True, text=True,
        )
        base = common.stdout.strip() if common.returncode == 0 else None
        if base is None and subprocess.run(
            ["git", "show-ref", "--verify", "--quiet", "refs/remotes/origin/main"], cwd=repo,
        ).returncode == 0:
            raise RuntimeError("[FAIL] No merge base with origin/main; fetch history or pass --format-base")
    else:
        resolved = subprocess.run(
            ["git", "rev-parse", "--verify", "--end-of-options", f"{base}^{{commit}}"],
            cwd=repo, capture_output=True, text=True,
        )
        if resolved.returncode != 0:
            raise RuntimeError(f"[FAIL] Invalid Dart format baseline: {base}")
        base = resolved.stdout.strip()
    commands = [
        (["git", "diff", "--name-only", "--diff-filter=ACMR", "-z", "HEAD"], False),
        (["git", "diff", "--name-only", "--diff-filter=ACMR", "-z", "HEAD^", "HEAD"], True),
        (["git", "ls-files", "--others", "--exclude-standard", "-z"], False),
    ]
    if base:
        commands.append((["git", "diff", "--name-only", "--diff-filter=ACMR", "-z", base, "HEAD", "--"], False))
    for command, allow_missing_parent in commands:
        proc = subprocess.run(command, cwd=repo, capture_output=True)
        if proc.returncode != 0:
            if allow_missing_parent:
                continue
            raise RuntimeError(f"[FAIL] Cannot determine changed Dart files: {' '.join(command[1:])}")
        for raw in proc.stdout.split(b"\x00"):
            if not raw:
                continue
            rel = raw.decode("utf-8", errors="replace")
            if rel.endswith(".dart"):
                full = (repo / rel).resolve()
                if full.is_file() and full.is_relative_to(app_dir.resolve()):
                    paths.add(str(full.relative_to(app_dir.resolve())).replace("\\", "/"))
    return sorted(paths)


def _should_allow_dev_metadata(repo: Path, release_flag: bool) -> bool:
    # Continuous-integration PRs can merge Z > 0 commits into main before formal
    # release freeze; the validator still enforces docs for marked candidates
    # and Z == 0. Explicit --release also checks unmarked versions strictly.
    del repo
    return not release_flag


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--mode",
        choices=("quick", "full"),
        default="quick",
        help="Quick directional checks (default) or full Flutter suite",
    )
    parser.add_argument(
        "--tests",
        nargs="*",
        default=[],
        help="Specific Flutter test files relative to local_app",
    )
    parser.add_argument(
        "--skip-flutter-tests",
        action="store_true",
        help="Skip running flutter test (useful for docs/tooling-only commits)",
    )
    parser.add_argument(
        "--release",
        action="store_true",
        help="Enforce formal release version metadata (never pass --allow-dev)",
    )
    parser.add_argument(
        "--format-base", help="Explicit Git baseline for Dart formatting; defaults to the origin/main merge base",
    )
    parser.add_argument(
        "--test-case-timeout",
        default=DEFAULT_TEST_CASE_TIMEOUT,
        help=(
            "Per-test timeout forwarded to `flutter test --timeout` "
            f"(default: {DEFAULT_TEST_CASE_TIMEOUT}; pass 'none' to disable)"
        ),
    )
    parser.add_argument(
        "--flutter-timeout",
        type=int,
        default=None,
        help=(
            "Outer hard wall-clock timeout in seconds for the flutter test process "
            f"(default: {DEFAULT_QUICK_FLUTTER_TIMEOUT_SECONDS}s quick / "
            f"{DEFAULT_FULL_FLUTTER_TIMEOUT_SECONDS}s full; <=0 disables)"
        ),
    )
    args = parser.parse_args(argv)
    if args.mode == "quick" and not args.tests and not args.skip_flutter_tests:
        print(
            "[FAIL] Quick mode requires --tests <files>, --mode full, or explicit "
            "--skip-flutter-tests (refusing to silently skip Flutter tests and pass).",
            file=sys.stderr,
        )
        return 2

    repo = Path(__file__).resolve().parents[1]
    app_dir = repo / "study_assistant-1.1.0" / "local_app"
    py = sys.executable
    dart_cmd = _resolve_tool("dart.bat", "dart")
    flutter_cmd = _resolve_tool("flutter.bat", "flutter")

    try:
        # 0. Git hooks activation check (local developer machines)
        if os.environ.get("CI", "").lower() != "true":
            hooks_proc = subprocess.run(
                ["git", "config", "--get", "core.hooksPath"],
                cwd=repo,
                capture_output=True,
                text=True,
            )
            hooks_path = hooks_proc.stdout.strip().replace("\\", "/")
            if hooks_path != ".githooks":
                raise RuntimeError(
                    "[FAIL] Git hooks not configured: expected core.hooksPath=.githooks "
                    f"(got {hooks_path!r}). Run: git config core.hooksPath .githooks"
                )
            print("[PASS] Git hooksPath (.githooks)")

        # 1. Repo safety check
        _run_step(
            "Repo safety scan (--worktree)",
            [py, str(repo / "scripts" / "check_repo_safety.py"), "--worktree"],
            repo,
        )

        # 2. L0 document line budget (AGENTS.md + PROJECT_STATE.md <= 80 lines)
        agents_lines = len((repo / "AGENTS.md").read_text(encoding="utf-8").splitlines())
        state_lines = len(
            (repo / "docs" / "ai-workflow" / "PROJECT_STATE.md")
            .read_text(encoding="utf-8")
            .splitlines()
        )
        total_lines = agents_lines + state_lines
        if total_lines > 80:
            raise RuntimeError(
                f"[FAIL] L0 doc line budget exceeded: AGENTS.md({agents_lines}) + PROJECT_STATE.md({state_lines}) = {total_lines} > 80"
            )
        print(
            f"[PASS] L0 doc line budget: {agents_lines} + {state_lines} = {total_lines} <= 80"
        )

        # 3. Release metadata check
        meta_cmd = [py, str(app_dir / "tool" / "check_release_metadata.py")]
        if _should_allow_dev_metadata(repo, args.release):
            meta_cmd.append("--allow-dev")
        _run_step("Release metadata check", meta_cmd, app_dir)

        # 4. Changed Dart formatting
        changed_dart = _changed_dart_files(repo, app_dir, args.format_base)
        if changed_dart:
            _run_step(
                f"Changed Dart format ({len(changed_dart)} files)",
                [dart_cmd, "format", "--output=none", "--set-exit-if-changed", *changed_dart],
                app_dir,
            )
        else:
            print("[SKIP] Changed Dart format (no changed .dart files)")

        # 5. Dart static analysis (never run flutter analyze in Chinese path)
        _run_step("Dart static analysis (lib, test)", [dart_cmd, "analyze", "lib", "test"], app_dir)

        # 6. Python scripts compile + unit tests
        py_files = sorted(
            str(p)
            for p in [
                *(repo / "scripts").glob("*.py"),
                *(app_dir / "tool").glob("*.py"),
            ]
        )
        _run_step("Python syntax compile", [py, "-m", "py_compile", *py_files], repo)
        for test_name in (
            "test_gitee_release_sync.py",
            "test_gitee_workflow.py",
            "test_verify_apk_and_report.py",
            "test_check_repo_safety.py",
            "test_verify_local_gate.py",
            "test_run_android_tests.py",
            "test_check_release_metadata.py",
            "test_freeze_release.py",
            "test_site_dispatch_workflow.py",
        ):
            _run_step(f"Python tests ({test_name})", [py, str(repo / "scripts" / test_name)], repo)

        # 7. Flutter tests
        if args.skip_flutter_tests:
            print("[SKIP] Flutter tests (--skip-flutter-tests)")
        elif args.tests or args.mode == "full":
            is_targeted = bool(args.tests)
            default_timeout = (
                DEFAULT_QUICK_FLUTTER_TIMEOUT_SECONDS
                if is_targeted
                else DEFAULT_FULL_FLUTTER_TIMEOUT_SECONDS
            )
            flutter_timeout = (
                args.flutter_timeout
                if args.flutter_timeout is not None
                else default_timeout
            )
            label = (
                f"Targeted Flutter tests ({len(args.tests)} files)"
                if is_targeted
                else "Full Flutter test suite"
            )
            _run_flutter_step(
                label,
                _build_flutter_test_cmd(
                    flutter_cmd,
                    args.tests if is_targeted else (),
                    test_case_timeout=args.test_case_timeout,
                ),
                app_dir,
                timeout_seconds=flutter_timeout,
            )
        else:
            print("[SKIP] Flutter tests (quick mode without --tests; pass --tests or --mode full)")
    except RuntimeError as err:
        print(str(err), file=sys.stderr)
        return 1

    print("[PASS] All selected local gate checks succeeded.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
