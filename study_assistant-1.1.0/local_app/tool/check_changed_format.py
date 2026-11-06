"""Check formatting only for Dart files changed by the current commit."""
from pathlib import Path
import subprocess
root = Path(__file__).resolve().parents[1]
repo = root.parents[1]
paths = subprocess.check_output(['git', 'diff', '--name-only', '--diff-filter=ACMR', '-z', 'HEAD^', 'HEAD'], cwd=repo).decode().split('\0')
files = [str(repo / p) for p in paths if p.endswith('.dart') and (repo / p).is_relative_to(root)]
if files:
    subprocess.run(['dart', 'format', '--output=none', '--set-exit-if-changed', *files], check=True)
