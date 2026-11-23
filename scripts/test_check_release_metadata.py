#!/usr/bin/env python3
"""Offline checks for the strict release metadata validator."""

from __future__ import annotations

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REAL_METADATA = (
    Path(__file__).resolve().parents[1]
    / "study_assistant-1.1.0"
    / "local_app"
    / "tool"
    / "check_release_metadata.py"
)


def _make_repo(raw_version: str) -> tuple[Path, Path]:
    repo = Path(tempfile.mkdtemp(prefix="release-meta-"))
    app = repo / "study_assistant-1.1.0" / "local_app"
    (app / "tool").mkdir(parents=True)
    (app / "lib" / "src" / "app").mkdir(parents=True)
    name, code = raw_version.split("+")
    (app / "pubspec.yaml").write_text(
        f"name: study_assistant_mobile\nversion: {raw_version}\n",
        encoding="utf-8",
    )
    (app / "lib" / "src" / "app" / "app_version.dart").write_text(
        "class AppVersion {\n"
        f"  static const name = '{name}';\n"
        f"  static const code = {code};\n"
        "}\n",
        encoding="utf-8",
    )
    shutil.copy2(REAL_METADATA, app / "tool" / "check_release_metadata.py")
    (repo / "CHANGELOG.md").write_text(
        f"## {name}（{code}）\n",
        encoding="utf-8",
    )
    (repo / "README.md").write_text(
        f"当前正式包为 {name}（{code}）\n",
        encoding="utf-8",
    )
    (repo / "docs" / "guides").mkdir(parents=True)
    (repo / "docs" / "guides" / "安装与使用.md").write_text(
        f"当前正式版本为 `{name}+{code}`\n",
        encoding="utf-8",
    )
    return repo, app / "tool" / "check_release_metadata.py"


def _run(script: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(script), *args],
        text=True,
        capture_output=True,
    )


class ReleaseMetadataTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dirs: list[Path] = []

    def tearDown(self) -> None:
        for path in self.temp_dirs:
            shutil.rmtree(path, ignore_errors=True)

    def _repo(self, version: str) -> Path:
        repo, script = _make_repo(version)
        self.temp_dirs.append(repo)
        return script

    def test_valid_formal_and_dev_versions(self) -> None:
        for version in ("1.8.26+120", "1.9.0+121"):
            result = _run(self._repo(version))
            self.assertEqual(0, result.returncode, result.stderr)
        result = _run(self._repo("1.9.0-dev.1+121"), "--allow-dev")
        self.assertEqual(0, result.returncode, result.stderr)

    def test_leading_zero_is_rejected_with_actionable_message(self) -> None:
        for version in ("1.9.00+121", "1.9.01+121", "1.09.0+121"):
            result = _run(self._repo(version))
            self.assertEqual(1, result.returncode)
            self.assertIn("leading zeros", result.stderr)

    def test_dev_requires_allow_dev(self) -> None:
        result = _run(self._repo("1.9.0-dev.1+121"))
        self.assertEqual(1, result.returncode)
        self.assertIn("dev suffix", result.stderr)


if __name__ == "__main__":
    unittest.main()
