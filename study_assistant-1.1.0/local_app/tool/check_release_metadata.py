"""Check version declarations without build tools or network."""
from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
repo = root.parents[1]
version = re.search(r'^version: ([0-9.]+)\+([0-9]+)$', (root / 'pubspec.yaml').read_text(encoding='utf-8'), re.M)
name, code = version.groups()
app = (root / 'lib/src/app/app_version.dart').read_text(encoding='utf-8')
assert f"name = '{name}'" in app and f'code = {code};' in app, 'AppVersion mismatch'
assert f'## {name}（{code}）' in (repo / 'CHANGELOG.md').read_text(encoding='utf-8'), 'Changelog missing'
assert f'{name}（{code}）' in (repo / 'README.md').read_text(encoding='utf-8'), 'README mismatch'
assert f'{name}+{code}' in (repo / 'docs/guides/安装与使用.md').read_text(encoding='utf-8'), 'Install guide mismatch'
print(f'Metadata consistent: {name}+{code}')
