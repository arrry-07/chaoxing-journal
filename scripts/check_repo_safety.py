#!/usr/bin/env python3
"""Repository safety gate for staged changes, commit ranges, and tracked worktree files."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess
import sys

MAX_BLOB_BYTES = 5 * 1024 * 1024
OVERSIZED_ALLOWLIST = {
    "study_assistant-1.1.0/local_app/assets/type/LXGWWenKaiScreen.ttf",
}

BLOCKED_EXTENSIONS = (".apk", ".aab", ".jks", ".keystore")
BLOCKED_BASENAMES = {"key.properties", "local.properties"}
BLOCKED_PREFIXES = (
    "docs/feedback/",
    "scripts/demo-video/",
    "docs/Gemini的迭代优化方案/",
)
BLOCKED_XML_RE = re.compile(
    r"^(?:FlutterSecureStorage|FlutterSharedPreferences).*\.xml$",
    re.IGNORECASE,
)

# Split sensitive literal tokens so this scanner file never self-matches.
SECRET_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    (
        "private-key-header",
        re.compile(r"-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE " + r"KEY-----"),
    ),
    (
        "keystore-password-literal",
        re.compile(r"(?i)\b(?:store" + r"Password|key" + r"Password)\s*=\s*\S+"),
    ),
    (
        "github-personal-access-token",
        re.compile(r"\b(?:gh" + r"p_[A-Za-z0-9]{20,}|github_" + r"pat_[A-Za-z0-9_]{20,})\b"),
    ),
    (
        "long-session-cookie",
        re.compile(r"(?i)\b(?:JSESSION" + r"ID|FI" + r"D|U" + r"F)=[A-Za-z0-9._-]{24,}"),
    ),
]


def normalize_path(path: str) -> str:
    return path.replace("\\", "/").lstrip("./")


def check_path(path: str) -> list[str]:
    norm = normalize_path(path)
    if not norm:
        return []
    violations: list[str] = []
    lower = norm.lower()
    if any(lower.endswith(ext) for ext in BLOCKED_EXTENSIONS):
        violations.append(f"[blocked-extension] {norm}")
    basename = norm.rsplit("/", 1)[-1]
    if basename.lower() in BLOCKED_BASENAMES:
        violations.append(f"[blocked-file] {norm}")
    if BLOCKED_XML_RE.match(basename):
        violations.append(f"[blocked-device-prefs] {norm}")
    if any(norm.startswith(prefix) for prefix in BLOCKED_PREFIXES):
        violations.append(f"[blocked-directory] {norm}")
    return violations


def check_blob_size(path: str, size_bytes: int) -> list[str]:
    norm = normalize_path(path)
    if size_bytes > MAX_BLOB_BYTES and norm not in OVERSIZED_ALLOWLIST:
        mb = size_bytes / (1024 * 1024)
        return [f"[oversized-blob] {norm} ({mb:.2f} MiB > 5 MiB limit)"]
    return []


def check_lines(path: str, lines: list[tuple[int, str]]) -> list[str]:
    norm = normalize_path(path)
    violations: list[str] = []
    for line_no, text in lines:
        for rule_name, pattern in SECRET_PATTERNS:
            if pattern.search(text):
                violations.append(f"[secret:{rule_name}] {norm}:{line_no}")
    return violations


def _git_bytes(repo: Path, args: list[str]) -> bytes:
    proc = subprocess.run(
        ["git", "-c", "core.quotePath=false", *args],
        cwd=repo,
        capture_output=True,
        check=True,
    )
    return proc.stdout


def _git_text(repo: Path, args: list[str]) -> str:
    return _git_bytes(repo, args).decode("utf-8", errors="replace")


def _split_nul_paths(raw: bytes) -> list[str]:
    if not raw:
        return []
    return [
        part.decode("utf-8", errors="replace")
        for part in raw.split(b"\x00")
        if part
    ]


def _parse_unified_zero_diff(diff_text: str) -> dict[str, list[tuple[int, str]]]:
    by_file: dict[str, list[tuple[int, str]]] = {}
    current_file: str | None = None
    next_line = 0
    for raw_line in diff_text.splitlines():
        if raw_line.startswith("+++ "):
            target = raw_line[4:].strip()
            if target == "/dev/null":
                current_file = None
            elif target.startswith("b/"):
                current_file = normalize_path(target[2:])
            else:
                current_file = normalize_path(target)
        elif raw_line.startswith("@@ "):
            m = re.search(r"\+(\d+)(?:,\d+)?", raw_line)
            if m:
                next_line = int(m.group(1))
        elif raw_line.startswith("+") and not raw_line.startswith("+++ "):
            if current_file is not None:
                by_file.setdefault(current_file, []).append((next_line, raw_line[1:]))
            next_line += 1
    return by_file


def scan_staged(repo: Path) -> list[str]:
    violations: list[str] = []
    paths = _split_nul_paths(
        _git_bytes(repo, ["diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z"])
    )
    for path in paths:
        violations.extend(check_path(path))
        size_raw = _git_text(repo, ["cat-file", "-s", f":{path}"]).strip()
        if size_raw.isdigit():
            violations.extend(check_blob_size(path, int(size_raw)))
    diff_text = _git_text(repo, ["diff", "--cached", "--unified=0", "--no-color", "-p"])
    for path, added in _parse_unified_zero_diff(diff_text).items():
        violations.extend(check_lines(path, added))
    return violations


def scan_range(repo: Path, revspec: str) -> list[str]:
    violations: list[str] = []
    if ".." in revspec:
        commits = [
            line.strip()
            for line in _git_text(repo, ["rev-list", revspec]).splitlines()
            if line.strip()
        ]
    else:
        commits = [
            line.strip()
            for line in _git_text(repo, ["rev-list", "-n", "1", revspec]).splitlines()
            if line.strip()
        ]
    for commit in commits:
        paths = _split_nul_paths(
            _git_bytes(
                repo,
                [
                    "diff-tree",
                    "--no-commit-id",
                    "--name-only",
                    "-r",
                    "--root",
                    "--diff-filter=ACMR",
                    "-z",
                    commit,
                ],
            )
        )
        for path in paths:
            violations.extend(check_path(path))
            size_raw = _git_text(repo, ["cat-file", "-s", f"{commit}:{path}"]).strip()
            if size_raw.isdigit():
                violations.extend(check_blob_size(path, int(size_raw)))
        diff_text = _git_text(
            repo,
            ["diff-tree", "-p", "--unified=0", "--no-color", "--root", commit],
        )
        for path, added in _parse_unified_zero_diff(diff_text).items():
            violations.extend(check_lines(path, added))
    return violations


def scan_worktree(repo: Path) -> list[str]:
    violations: list[str] = []
    tracked = set(
        _split_nul_paths(_git_bytes(repo, ["ls-files", "-z"]))
    )
    staged = set(
        _split_nul_paths(
            _git_bytes(repo, ["diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z"])
        )
    )
    deleted_staged = set(
        _split_nul_paths(
            _git_bytes(repo, ["diff", "--cached", "--name-only", "--diff-filter=D", "-z"])
        )
    )
    candidates = sorted((tracked - deleted_staged) | staged)
    for path in candidates:
        violations.extend(check_path(path))
        disk_path = repo / path
        if path in staged:
            size_raw = _git_text(repo, ["cat-file", "-s", f":{path}"]).strip()
            if size_raw.isdigit():
                violations.extend(check_blob_size(path, int(size_raw)))
            raw_bytes = _git_bytes(repo, ["cat-file", "-p", f":{path}"])
        elif disk_path.is_file():
            violations.extend(check_blob_size(path, disk_path.stat().st_size))
            raw_bytes = disk_path.read_bytes()
        else:
            continue
        if b"\x00" in raw_bytes[:8192]:
            continue
        lines = [
            (idx + 1, line)
            for idx, line in enumerate(
                raw_bytes.decode("utf-8", errors="replace").splitlines()
            )
        ]
        violations.extend(check_lines(path, lines))
    return violations


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--staged", action="store_true", help="Inspect staged changes")
    mode.add_argument("--range", metavar="REVSPEC", help="Inspect commit(s) in range")
    mode.add_argument(
        "--worktree",
        action="store_true",
        help="Inspect all tracked and staged repository files",
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Git repository root",
    )
    args = parser.parse_args(argv)
    repo = args.repo_root.resolve()

    if args.staged:
        violations = scan_staged(repo)
        scope = "staged"
    elif args.range is not None:
        violations = scan_range(repo, args.range)
        scope = f"range({args.range})"
    else:
        violations = scan_worktree(repo)
        scope = "worktree"

    if violations:
        print(f"[FAIL] Repo safety gate blocked ({scope}):", file=sys.stderr)
        for item in violations:
            print(f"  - {item}", file=sys.stderr)
        return 1
    print(f"[PASS] Repo safety check clean ({scope})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
