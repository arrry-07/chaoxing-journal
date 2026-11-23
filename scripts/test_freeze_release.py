#!/usr/bin/env python3
"""Offline checks for scripts/freeze_release.py."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parent
FREEZE = SCRIPTS / "freeze_release.py"
METADATA = (
    SCRIPTS.parent
    / "study_assistant-1.1.0"
    / "local_app"
    / "tool"
    / "check_release_metadata.py"
)
SPEC = importlib.util.spec_from_file_location("freeze_release", FREEZE)
assert SPEC and SPEC.loader
freeze = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = freeze
SPEC.loader.exec_module(freeze)


README = """# 项目

**[下载 Android 安装包：1.8.26+120](https://github.com/arrry-07/chaoxing-journal/releases/download/v1.8.26/chaoxing-journal-1.8.26.apk)** · [发布说明](https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.8.26)

**1.8.26+120 已正式发布。**

**当前正式包为 1.8.26（120）；已安装用户直接覆盖安装。**

1. [下载 chaoxing-journal-1.8.26.apk](https://github.com/arrry-07/chaoxing-journal/releases/download/v1.8.26/chaoxing-journal-1.8.26.apk)。

<summary>已经安装：如何升级到 1.8.26？</summary>
"""

INSTALL = """# 安装与使用

当前正式版本为 `1.8.26+120`。

[下载 chaoxing-journal-1.8.26.apk](https://github.com/arrry-07/chaoxing-journal/releases/download/v1.8.26/chaoxing-journal-1.8.26.apk)，并从[同一发布页](https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.8.26)下载校验文件。

Get-FileHash -Algorithm SHA256 -LiteralPath .\\chaoxing-journal-1.8.26.apk
"""


def _make_repo(
    version: str = "1.8.26+120",
    *,
    changelog_new: str | None = None,
) -> Path:
    repo = Path(tempfile.mkdtemp(prefix="freeze-release-"))
    app = repo / "study_assistant-1.1.0" / "local_app"
    (app / "tool").mkdir(parents=True)
    (app / "lib" / "src" / "app").mkdir(parents=True)
    name, code = version.split("+")
    (app / "pubspec.yaml").write_text(
        f"name: study_assistant_mobile\nversion: {version}\n",
        encoding="utf-8",
    )
    (app / "lib" / "src" / "app" / "app_version.dart").write_text(
        "class AppVersion {\n"
        f"  static const name = '{name}';\n"
        f"  static const code = {code};\n"
        "}\n",
        encoding="utf-8",
    )
    shutil.copy2(METADATA, app / "tool" / "check_release_metadata.py")
    (repo / "CHANGELOG.md").write_text(
        "## 1.8.26（120）\n" + (changelog_new or ""),
        encoding="utf-8",
    )
    (repo / "README.md").write_text(README, encoding="utf-8")
    (repo / "docs" / "guides").mkdir(parents=True)
    (repo / "docs" / "guides" / "安装与使用.md").write_text(
        INSTALL,
        encoding="utf-8",
    )
    return repo


def _run(script: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(script), *args],
        text=True,
        capture_output=True,
    )


class FreezeReleaseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.repos: list[Path] = []

    def tearDown(self) -> None:
        for repo in self.repos:
            shutil.rmtree(repo, ignore_errors=True)

    def _repo(self, version: str = "1.8.26+120", **kwargs: str) -> Path:
        repo = _make_repo(version, **kwargs)
        self.repos.append(repo)
        return repo

    def test_check_current_release(self) -> None:
        repo = self._repo()
        result = _run(FREEZE, "--check", "--root", str(repo))
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("1.8.26+120", result.stdout)

    def test_apply_dev_version_updates_only_app_identity(self) -> None:
        repo = self._repo()
        result = _run(
            FREEZE,
            "--apply",
            "--version",
            "1.9.0-dev.1+121",
            "--root",
            str(repo),
        )
        self.assertEqual(0, result.returncode, result.stderr)
        pubspec = (repo / "study_assistant-1.1.0/local_app/pubspec.yaml").read_text(
            encoding="utf-8"
        )
        self.assertIn("version: 1.9.0-dev.1+121", pubspec)
        self.assertIn(
            "static const name = '1.9.0-dev.1';",
            (repo / "study_assistant-1.1.0/local_app/lib/src/app/app_version.dart")
            .read_text(encoding="utf-8"),
        )
        metadata = _run(
            repo / "study_assistant-1.1.0/local_app/tool/check_release_metadata.py",
            "--allow-dev",
        )
        self.assertEqual(0, metadata.returncode, metadata.stderr)
        self.assertIn("1.8.26", (repo / "README.md").read_text(encoding="utf-8"))

    def test_apply_formal_version_updates_links_and_classifies_minor(self) -> None:
        repo = self._repo(changelog_new="## 1.9.0（121）\n")
        result = _run(
            FREEZE,
            "--apply",
            "--version",
            "1.9.0+121",
            "--previous",
            "1.8.26+120",
            "--root",
            str(repo),
        )
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("minor", result.stdout)
        readme = (repo / "README.md").read_text(encoding="utf-8")
        install = (repo / "docs/guides/安装与使用.md").read_text(encoding="utf-8")
        self.assertIn("下载 Android 安装包：1.9.0+121", readme)
        self.assertIn("releases/tag/v1.9.0", readme)
        self.assertIn("chaoxing-journal-1.9.0.apk", readme)
        self.assertIn("当前正式版本为 `1.9.0+121`", install)
        self.assertNotIn("chaoxing-journal-1.8.26.apk", readme)
        metadata = _run(
            repo / "study_assistant-1.1.0/local_app/tool/check_release_metadata.py"
        )
        self.assertEqual(0, metadata.returncode, metadata.stderr)
        check = _run(FREEZE, "--check", "--root", str(repo), "--previous", "1.8.26+120")
        self.assertEqual(0, check.returncode, check.stderr)
        self.assertIn("Update level: minor", check.stdout)

    def test_leading_zero_and_build_regression_are_rejected(self) -> None:
        repo = self._repo()
        leading = _run(
            FREEZE,
            "--apply",
            "--version",
            "1.9.00+121",
            "--root",
            str(repo),
        )
        self.assertEqual(1, leading.returncode)
        self.assertIn("leading zeros", leading.stderr)

        regression = _run(
            FREEZE,
            "--apply",
            "--version",
            "1.9.0+120",
            "--previous",
            "1.8.26+120",
            "--root",
            str(repo),
        )
        self.assertEqual(1, regression.returncode)
        self.assertIn("Build code", regression.stderr)

    def test_formal_apply_requires_changelog_heading(self) -> None:
        repo = self._repo()
        result = _run(
            FREEZE,
            "--apply",
            "--version",
            "1.9.0+121",
            "--root",
            str(repo),
        )
        self.assertEqual(1, result.returncode)
        self.assertIn("CHANGELOG.md", result.stderr)

    def test_update_levels(self) -> None:
        base = freeze.parse_version("1.9.0+121")
        self.assertEqual(
            "patch",
            freeze.classify_update(base, freeze.parse_version("1.9.1+122")),
        )
        self.assertEqual(
            "minor",
            freeze.classify_update(base, freeze.parse_version("1.10.0+130")),
        )
        self.assertEqual(
            "major",
            freeze.classify_update(base, freeze.parse_version("2.0.0+200")),
        )


if __name__ == "__main__":
    unittest.main()
