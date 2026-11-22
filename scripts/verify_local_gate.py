#!/usr/bin/env python3
"""Unified local verification gate matching repository AGENTS & VALIDATION rules."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


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


def _changed_dart_files(repo: Path, app_dir: Path) -> list[str]:
    paths: set[str] = set()
    for args in (
        ["git", "-c", "core.quotePath=false", "diff", "--name-only", "--diff-filter=ACMR", "-z", "HEAD"],
        ["git", "-c", "core.quotePath=false", "diff", "--name-only", "--diff-filter=ACMR", "-z", "HEAD^", "HEAD"],
    ):
        proc = subprocess.run(args, cwd=repo, capture_output=True)
        if proc.returncode != 0:
            continue
        for raw in proc.stdout.split(b"\x00"):
            if not raw:
                continue
            rel = raw.decode("utf-8", errors="replace")
            if rel.endswith(".dart"):
                full = (repo / rel).resolve()
                if full.is_file() and full.is_relative_to(app_dir.resolve()):
                    paths.add(str(full.relative_to(app_dir.resolve())).replace("\\", "/"))
    return sorted(paths)


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
    args = parser.parse_args(argv)

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
        pubspec = (app_dir / "pubspec.yaml").read_text(encoding="utf-8")
        is_dev = bool(re.search(r"^version:\s*\d+\.\d+\.\d+-dev\.", pubspec, re.M))
        meta_cmd = [py, str(app_dir / "tool" / "check_release_metadata.py")]
        if is_dev and not args.release:
            meta_cmd.append("--allow-dev")
        _run_step("Release metadata check", meta_cmd, app_dir)

        # 4. Changed Dart formatting
        changed_dart = _changed_dart_files(repo, app_dir)
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
        ):
            _run_step(f"Python tests ({test_name})", [py, str(repo / "scripts" / test_name)], repo)

        # 7. Flutter tests
        if args.skip_flutter_tests:
            print("[SKIP] Flutter tests (--skip-flutter-tests)")
        elif args.tests:
            _run_step(
                f"Targeted Flutter tests ({len(args.tests)} files)",
                [flutter_cmd, "--no-version-check", "test", "--no-pub", *args.tests],
                app_dir,
            )
        elif args.mode == "full":
            _run_step(
                "Full Flutter test suite",
                [flutter_cmd, "--no-version-check", "test", "--no-pub"],
                app_dir,
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
