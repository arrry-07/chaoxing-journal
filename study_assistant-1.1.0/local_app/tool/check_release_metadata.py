"""Check version declarations without build tools or network."""
import argparse
from pathlib import Path
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--allow-dev", action="store_true", help="Accept a dev build for local or manual CI checks")
args = parser.parse_args()

root = Path(__file__).resolve().parents[1]
repo = root.parents[1]
version = re.search(
    r"^version: (\d+\.\d+\.\d+)(-dev\.[1-9]\d*)?\+([1-9]\d*)$",
    (root / "pubspec.yaml").read_text(encoding="utf-8"),
    re.M,
)
if version is None:
    parser.exit(1, "Expected X.Y.Z+build or X.Y.Z-dev.N+build in pubspec.yaml\n")

base_name, dev_suffix, code = version.groups()
if dev_suffix and not args.allow_dev:
    parser.exit(1, "Release metadata requires X.Y.Z+build without a dev suffix\n")

name = base_name + (dev_suffix or "")
app = (root / 'lib/src/app/app_version.dart').read_text(encoding='utf-8')
assert f"name = '{name}'" in app and f'code = {code};' in app, 'AppVersion mismatch'
if not dev_suffix:
    assert f'## {name}（{code}）' in (repo / 'CHANGELOG.md').read_text(encoding='utf-8'), 'Changelog missing'
    assert f'{name}（{code}）' in (repo / 'README.md').read_text(encoding='utf-8'), 'README mismatch'
    assert f'{name}+{code}' in (repo / 'docs/guides/安装与使用.md').read_text(encoding='utf-8'), 'Install guide mismatch'
print(f'Metadata consistent: {name}+{code}')
