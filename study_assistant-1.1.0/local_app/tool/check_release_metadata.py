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
version = re.search(
    r"^version: ((?:0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*))\+([1-9]\d*)\r?$",
    (root / "pubspec.yaml").read_text(encoding="utf-8"),
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
app = (root / 'lib/src/app/app_version.dart').read_text(encoding='utf-8')
assert f"name = '{name}'" in app and f'code = {code};' in app, 'AppVersion mismatch'
if args.tag is not None and args.tag != f"v{name}":
    parser.exit(
        1,
        f"Tag mismatch: tag {args.tag!r} does not match pubspec version 'v{name}'\n",
    )
if not (args.allow_dev and int(patch) > 0):
    assert f'## {name}（{code}）' in (repo / 'CHANGELOG.md').read_text(encoding='utf-8'), 'Changelog missing'
    assert f'{name}（{code}）' in (repo / 'README.md').read_text(encoding='utf-8'), 'README mismatch'
    assert f'{name}+{code}' in (repo / 'docs/guides/安装与使用.md').read_text(encoding='utf-8'), 'Install guide mismatch'
print(f'Metadata consistent: {name}+{code}')
