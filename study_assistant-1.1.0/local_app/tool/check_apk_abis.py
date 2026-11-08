"""Verify that an APK advertises only ABI directories with a Flutter engine."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys
import zipfile


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("apk", type=Path)
    parser.add_argument(
        "--abi",
        action="append",
        dest="abis",
        required=True,
        help="Supported ABI; repeat for each expected ABI",
    )
    args = parser.parse_args()

    if not args.apk.is_file():
        parser.error(f"APK not found: {args.apk}")

    expected = set(args.abis)
    with zipfile.ZipFile(args.apk) as archive:
        native_entries = [
            name
            for name in archive.namelist()
            if name.startswith("lib/") and name.endswith(".so")
        ]

    observed = {
        name.split("/", 2)[1]
        for name in native_entries
        if len(name.split("/", 2)) == 3
    }
    failures: list[str] = []

    unexpected = sorted(observed - expected)
    if unexpected:
        failures.append(f"unexpected ABI directories: {', '.join(unexpected)}")

    for abi in sorted(expected):
        engine = f"lib/{abi}/libflutter.so"
        if engine not in native_entries:
            failures.append(f"{abi} has no libflutter.so")

    if failures:
        for failure in failures:
            print(f"ERROR: {failure}", file=sys.stderr)
        return 1

    print(f"APK ABI check passed: {', '.join(sorted(expected))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
