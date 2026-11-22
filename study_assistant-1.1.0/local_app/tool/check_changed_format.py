"""Check formatting only for Dart files changed relative to a base ref (default: HEAD^)."""
from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import subprocess


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base",
        default="HEAD^",
        help="Base git revision to diff against HEAD (default: HEAD^)",
    )
    args = parser.parse_args(argv)

    root = Path(__file__).resolve().parents[1]
    repo = root.parents[1]
    raw = subprocess.check_output(
        [
            "git",
            "-c",
            "core.quotePath=false",
            "diff",
            "--name-only",
            "--diff-filter=ACMR",
            "-z",
            args.base,
            "HEAD",
        ],
        cwd=repo,
    )
    paths = [
        part.decode("utf-8", errors="replace")
        for part in raw.split(b"\x00")
        if part
    ]
    files = [
        str(repo / p)
        for p in paths
        if p.endswith(".dart") and (repo / p).is_relative_to(root) and (repo / p).is_file()
    ]
    if files:
        dart_cmd = shutil.which("dart.bat") or shutil.which("dart") or "dart"
        subprocess.run(
            [dart_cmd, "format", "--output=none", "--set-exit-if-changed", *files],
            check=True,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
