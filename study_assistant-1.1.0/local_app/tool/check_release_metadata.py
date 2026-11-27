"""Check version declarations without build tools or network."""
import argparse
from pathlib import Path
import re

parser = argparse.ArgumentParser(description=__doc__)
mode_group = parser.add_mutually_exclusive_group()
mode_group.add_argument(
    "--allow-dev",
    action="store_true",
    help="Accept a dev test package (X.Y.Z with Z > 0) without formal release docs",
)
mode_group.add_argument(
    "--tag",
    help="Verify strict formal release metadata against a Git tag such as v1.92.0",
)
args = parser.parse_args()

root = Path(__file__).resolve().parents[1]
repo = root.parents[1]
pubspec = (root / "pubspec.yaml").read_text(encoding="utf-8")
version = re.search(
    r"^version: ((?:0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*))\+([1-9]\d*)\r?$",
    pubspec,
    re.M,
)
if version is None:
    parser.exit(
        1,
        "Expected X.Y.Z+build without leading zeros or a -dev.N suffix "
        "(for example 1.90.0+123, not 1.90.00+123) in pubspec.yaml\n",
    )

base_name, minor, patch, code = version.groups()
if int(minor) > 99:
    parser.exit(
        1,
        "Minor version Y must be <= 99; bump the major version instead "
        f"(got {base_name})\n",
    )

name = base_name
formal_marks = [mark.strip() for mark in re.findall(r"^# formal-release:([^\r\n]*)", pubspec, re.M)]
if formal_marks and formal_marks != [f"{name}+{code}"]:
    parser.exit(1, "Formal release marker must match the single pubspec version. Use freeze_release.py.\n")
app = (root / 'lib/src/app/app_version.dart').read_text(encoding='utf-8')
if f"name = '{name}'" not in app or f'code = {code};' not in app:
    parser.exit(1, "AppVersion mismatch\n")
if args.tag is not None and args.tag != f"v{name}":
    parser.exit(
        1,
        f"Tag mismatch: tag {args.tag!r} does not match pubspec version 'v{name}'\n",
    )
if formal_marks or not (args.allow_dev and int(patch) > 0):
    for path, expected, message in (
        ("CHANGELOG.md", f"## {name}（{code}）", "Changelog missing"),
        ("README.md", f"{name}（{code}）", "README mismatch"),
        ("docs/guides/安装与使用.md", f"{name}+{code}", "Install guide mismatch"),
    ):
        document = repo / path
        if not document.is_file() or expected not in document.read_text(encoding="utf-8"):
            parser.exit(1, f"{message}: {path}\n")
print(f'Metadata consistent: {name}+{code}')
