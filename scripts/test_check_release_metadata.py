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


def _make_repo(raw_version: str, *, newline: str = "\n") -> tuple[Path, Path]:
    repo = Path(tempfile.mkdtemp(prefix="release-meta-"))
    app = repo / "study_assistant-1.1.0" / "local_app"
    (app / "tool").mkdir(parents=True)
    (app / "lib" / "src" / "app").mkdir(parents=True)
    name, code = raw_version.split("+")
    files = {
        app / "pubspec.yaml": (
            f"name: study_assistant_mobile{newline}version: {raw_version}{newline}"
        ),
        app / "lib" / "src" / "app" / "app_version.dart": (
            "class AppVersion {" + newline
            + f"  static const name = '{name}';" + newline
            + f"  static const code = {code};" + newline
            + "}" + newline
        ),
        repo / "CHANGELOG.md": f"## {name}（{code}）{newline}",
        repo / "README.md": f"当前正式包为 {name}（{code}）{newline}",
        repo / "docs" / "guides" / "安装与使用.md": (
            f"当前正式版本为 `{name}+{code}`{newline}"
        ),
    }
    for path, text in files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8", newline="")
    shutil.copy2(REAL_METADATA, app / "tool" / "check_release_metadata.py")
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

    def _repo(self, version: str, *, newline: str = "\n") -> Path:
        repo, script = _make_repo(version, newline=newline)
        self.temp_dirs.append(repo)
        return script

    def test_formal_version_requires_docs(self) -> None:
        result = _run(self._repo("1.90.0+123"))
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("1.90.0+123", result.stdout)

    def test_dev_version_passes_with_allow_dev_and_keeps_formal_docs(self) -> None:
        script = self._repo("1.8.27+121")
        result = _run(script, "--allow-dev")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("1.8.27+121", result.stdout)

    def test_dev_version_without_allow_dev_is_rejected(self) -> None:
        result = _run(self._repo("1.8.27+121"))
        self.assertEqual(1, result.returncode)
        self.assertIn("Formal release metadata requires X.Y.0", result.stderr)

    def test_dev_suffix_is_rejected(self) -> None:
        result = _run(self._repo("1.90.0-dev.1+123"), "--allow-dev")
        self.assertEqual(1, result.returncode)
        self.assertIn("-dev.N", result.stderr)

    def test_leading_zero_is_rejected_with_actionable_message(self) -> None:
        for version in ("1.9.00+121", "1.90.00+123", "1.9.01+121", "1.09.0+121"):
            result = _run(self._repo(version))
            self.assertEqual(1, result.returncode, version)
            self.assertIn("leading zeros", result.stderr)

    def test_minor_version_over_99_is_rejected(self) -> None:
        result = _run(self._repo("1.100.0+121"))
        self.assertEqual(1, result.returncode)
        self.assertIn("must be <= 99", result.stderr)

    def test_crlf_pubspec_is_accepted(self) -> None:
        result = _run(self._repo("1.90.0+123", newline="\r\n"))
        self.assertEqual(0, result.returncode, result.stderr)


if __name__ == "__main__":
    unittest.main()
