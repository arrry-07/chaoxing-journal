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


README_TEMPLATE = """# 项目

**[下载 Android 安装包：{raw}](https://github.com/arrry-07/chaoxing-journal/releases/download/v{name}/chaoxing-journal-{name}.apk)** · [发布说明](https://github.com/arrry-07/chaoxing-journal/releases/tag/v{name})

**{raw} 已正式发布。**

**当前正式包为 {name}（{code}）；已安装用户直接覆盖安装。**

1. [下载 chaoxing-journal-{name}.apk](https://github.com/arrry-07/chaoxing-journal/releases/download/v{name}/chaoxing-journal-{name}.apk)。发布说明及校验文件见 [{name} 发布页](https://github.com/arrry-07/chaoxing-journal/releases/tag/v{name})。

<summary>已经安装：如何升级到 {name}？</summary>

正式包使用体验证书，{name} 继续沿用既有包名与体验证书。
"""

INSTALL_TEMPLATE = """# 安装与使用

当前正式版本为 `{raw}`。

[下载 chaoxing-journal-{name}.apk](https://github.com/arrry-07/chaoxing-journal/releases/download/v{name}/chaoxing-journal-{name}.apk)，并从[同一发布页](https://github.com/arrry-07/chaoxing-journal/releases/tag/v{name})下载校验文件。

Get-FileHash -Algorithm SHA256 -LiteralPath .\\chaoxing-journal-{name}.apk
"""


def _docs(version: str, newline: str) -> tuple[str, str]:
    name, code = version.split("+")
    fields = {"raw": version, "name": name, "code": code}
    readme = README_TEMPLATE.format(**fields).replace("\n", newline)
    install = INSTALL_TEMPLATE.format(**fields).replace("\n", newline)
    return readme, install


def _make_repo(
    version: str = "1.8.26+120",
    *,
    formal: str = "1.8.26+120",
    changelog_new: str | None = None,
    newline: str = "\n",
) -> Path:
    repo = Path(tempfile.mkdtemp(prefix="freeze-release-"))
    app = repo / "study_assistant-1.1.0" / "local_app"
    (app / "tool").mkdir(parents=True)
    (app / "lib" / "src" / "app").mkdir(parents=True)
    name, code = version.split("+")
    dart = newline.join(
        [
            "class AppVersion {",
            f"  static const name = '{name}';",
            f"  static const code = {code};",
            "}",
            "",
        ]
    )
    (app / "pubspec.yaml").write_text(
        f"name: study_assistant_mobile{newline}version: {version}{newline}",
        encoding="utf-8",
        newline="",
    )
    (app / "lib" / "src" / "app" / "app_version.dart").write_text(
        dart,
        encoding="utf-8",
        newline="",
    )
    shutil.copy2(METADATA, app / "tool" / "check_release_metadata.py")
    changelog_header = f"## {formal.split('+')[0]}（{formal.split('+')[1]}）"
    (repo / "CHANGELOG.md").write_text(
        changelog_header + newline + (changelog_new or ""),
        encoding="utf-8",
        newline="",
    )
    readme, install = _docs(formal, newline)
    (repo / "README.md").write_text(readme, encoding="utf-8", newline="")
    (repo / "docs" / "guides").mkdir(parents=True)
    (repo / "docs" / "guides" / "安装与使用.md").write_text(
        install,
        encoding="utf-8",
        newline="",
    )
    return repo


def _run(script: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(script), *args],
        text=True,
        capture_output=True,
    )


def _read(path: Path) -> str:
    with path.open("r", encoding="utf-8", newline="") as handle:
        return handle.read()


class FreezeReleaseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.repos: list[Path] = []

    def tearDown(self) -> None:
        for repo in self.repos:
            shutil.rmtree(repo, ignore_errors=True)

    def _repo(
        self,
        version: str = "1.8.26+120",
        *,
        formal: str = "1.8.26+120",
        changelog_new: str | None = None,
        newline: str = "\n",
    ) -> Path:
        repo = _make_repo(
            version,
            formal=formal,
            changelog_new=changelog_new,
            newline=newline,
        )
        self.repos.append(repo)
        return repo

    def test_check_infers_dev_mode_for_patch_package(self) -> None:
        repo = self._repo()
        result = _run(FREEZE, "--check", "--root", str(repo))
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("dev test package", result.stdout)
        self.assertIn("1.8.26+120", result.stdout)

        formal = _run(FREEZE, "--check", "--mode", "formal", "--root", str(repo))
        self.assertEqual(1, formal.returncode)
        self.assertIn("end with .0", formal.stderr)

    def test_apply_dev_version_updates_only_app_identity(self) -> None:
        repo = self._repo()
        result = _run(
            FREEZE,
            "--apply",
            "--mode",
            "dev",
            "--version",
            "1.8.27+121",
            "--root",
            str(repo),
        )
        self.assertEqual(0, result.returncode, result.stderr)
        app = repo / "study_assistant-1.1.0/local_app"
        self.assertIn("version: 1.8.27+121", _read(app / "pubspec.yaml"))
        self.assertIn(
            "static const name = '1.8.27';",
            _read(app / "lib/src/app/app_version.dart"),
        )
        self.assertIn("当前正式包为 1.8.26（120）", _read(repo / "README.md"))
        metadata = _run(app / "tool" / "check_release_metadata.py", "--allow-dev")
        self.assertEqual(0, metadata.returncode, metadata.stderr)
        self.assertNotIn("-dev.", _read(app / "pubspec.yaml"))

    def test_dev_apply_rejects_zero_patch(self) -> None:
        repo = self._repo()
        result = _run(
            FREEZE,
            "--apply",
            "--mode",
            "dev",
            "--version",
            "1.9.0+121",
            "--root",
            str(repo),
        )
        self.assertEqual(1, result.returncode)
        self.assertIn("increment Z", result.stderr)

    def test_apply_formal_version_updates_links_and_classifies_minor(self) -> None:
        repo = self._repo(
            "1.8.27+121",
            changelog_new="## 1.9.0（122）\n",
        )
        result = _run(
            FREEZE,
            "--apply",
            "--mode",
            "formal",
            "--version",
            "1.9.0+122",
            "--previous",
            "1.8.26+120",
            "--root",
            str(repo),
        )
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("minor", result.stdout)
        readme = _read(repo / "README.md")
        install = _read(repo / "docs/guides/安装与使用.md")
        self.assertIn("下载 Android 安装包：1.9.0+122", readme)
        self.assertIn("[1.9.0 发布页]", readme)
        self.assertIn("1.9.0 继续沿用", readme)
        self.assertIn("releases/tag/v1.9.0", readme)
        self.assertIn("chaoxing-journal-1.9.0.apk", readme)
        self.assertIn("当前正式版本为 `1.9.0+122`", install)
        self.assertNotIn("chaoxing-journal-1.8.26.apk", readme)
        self.assertNotIn("1.8.26", readme)
        metadata = _run(
            repo / "study_assistant-1.1.0/local_app/tool/check_release_metadata.py"
        )
        self.assertEqual(0, metadata.returncode, metadata.stderr)
        check = _run(
            FREEZE,
            "--check",
            "--mode",
            "formal",
            "--root",
            str(repo),
            "--previous",
            "1.8.26+120",
        )
        self.assertEqual(0, check.returncode, check.stderr)
        self.assertIn("Update level: minor", check.stdout)

    def test_formal_apply_detects_previous_release_from_docs(self) -> None:
        repo = self._repo(
            "1.8.27+121",
            changelog_new="## 1.9.0（122）\n",
        )
        result = _run(
            FREEZE,
            "--apply",
            "--mode",
            "formal",
            "--version",
            "1.9.0+122",
            "--root",
            str(repo),
        )
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("1.9.0+122", _read(repo / "README.md"))

    def test_formal_apply_requires_expected_minor_step(self) -> None:
        repo = self._repo(changelog_new="## 1.10.0（121）\n")
        result = _run(
            FREEZE,
            "--apply",
            "--mode",
            "formal",
            "--version",
            "1.10.0+121",
            "--previous",
            "1.8.26+120",
            "--root",
            str(repo),
        )
        self.assertEqual(1, result.returncode)
        self.assertIn("must be 1.9.0", result.stderr)

    def test_minor_99_rolls_into_new_major(self) -> None:
        repo = self._repo(
            "1.99.0+150",
            formal="1.99.0+150",
            changelog_new="## 2.0.0（151）\n",
        )
        result = _run(
            FREEZE,
            "--apply",
            "--mode",
            "formal",
            "--version",
            "2.0.0+151",
            "--previous",
            "1.99.0+150",
            "--root",
            str(repo),
        )
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("major", result.stdout)
        self.assertIn("当前正式包为 2.0.0（151）", _read(repo / "README.md"))

    def test_minor_version_over_99_is_rejected(self) -> None:
        repo = self._repo(changelog_new="## 1.100.0（121）\n")
        result = _run(
            FREEZE,
            "--apply",
            "--mode",
            "formal",
            "--version",
            "1.100.0+121",
            "--root",
            str(repo),
        )
        self.assertEqual(1, result.returncode)
        self.assertIn("must be <= 99", result.stderr)

    def test_leading_zero_and_build_regression_are_rejected(self) -> None:
        repo = self._repo()
        leading = _run(
            FREEZE,
            "--apply",
            "--mode",
            "dev",
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
            "--mode",
            "formal",
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
        repo = self._repo("1.8.27+121")
        result = _run(
            FREEZE,
            "--apply",
            "--mode",
            "formal",
            "--version",
            "1.9.0+122",
            "--root",
            str(repo),
        )
        self.assertEqual(1, result.returncode)
        self.assertIn("CHANGELOG.md", result.stderr)

    def test_apply_preserves_crlf_line_endings(self) -> None:
        repo = self._repo(newline="\r\n")
        app = repo / "study_assistant-1.1.0/local_app"
        dev = _run(
            FREEZE,
            "--apply",
            "--mode",
            "dev",
            "--version",
            "1.8.27+121",
            "--root",
            str(repo),
        )
        self.assertEqual(0, dev.returncode, dev.stderr)
        for path in (app / "pubspec.yaml", app / "lib/src/app/app_version.dart"):
            text = _read(path)
            self.assertEqual(text.count("\n"), text.count("\r\n"), path)

        formal = _run(
            FREEZE,
            "--apply",
            "--mode",
            "formal",
            "--version",
            "1.9.0+122",
            "--previous",
            "1.8.26+120",
            "--root",
            str(repo),
        )
        self.assertEqual(1, formal.returncode)
        self.assertIn("CHANGELOG.md", formal.stderr)
        (repo / "CHANGELOG.md").write_text(
            "## 1.8.26（120）\r\n## 1.9.0（122）\r\n",
            encoding="utf-8",
            newline="",
        )
        formal = _run(
            FREEZE,
            "--apply",
            "--mode",
            "formal",
            "--version",
            "1.9.0+122",
            "--previous",
            "1.8.26+120",
            "--root",
            str(repo),
        )
        self.assertEqual(0, formal.returncode, formal.stderr)
        for path in (
            app / "pubspec.yaml",
            app / "lib/src/app/app_version.dart",
            repo / "README.md",
            repo / "docs/guides/安装与使用.md",
        ):
            text = _read(path)
            self.assertEqual(text.count("\n"), text.count("\r\n"), path)

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
