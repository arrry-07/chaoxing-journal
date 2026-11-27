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


def _make_repo(
    raw_version: str,
    *,
    formal_version: str | None = None,
    newline: str = "\n",
) -> tuple[Path, Path]:
    repo = Path(tempfile.mkdtemp(prefix="release-meta-"))
    app = repo / "study_assistant-1.1.0" / "local_app"
    (app / "tool").mkdir(parents=True)
    (app / "lib" / "src" / "app").mkdir(parents=True)
    name, code = raw_version.split("+")
    formal_name, formal_code = (formal_version or raw_version).split("+")
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
        repo / "CHANGELOG.md": f"## {formal_name}（{formal_code}）{newline}",
        repo / "README.md": f"当前正式包为 {formal_name}（{formal_code}）{newline}",
        repo / "docs" / "guides" / "安装与使用.md": (
            f"当前正式版本为 `{formal_name}+{formal_code}`{newline}"
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

    def _repo(
        self,
        version: str,
        *,
        formal_version: str | None = None,
        newline: str = "\n",
    ) -> Path:
        repo, script = _make_repo(
            version,
            formal_version=formal_version,
            newline=newline,
        )
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

    def test_unfrozen_dev_version_without_allow_dev_is_rejected(self) -> None:
        repo, script = _make_repo("1.8.27+121")
        self.temp_dirs.append(repo)
        (repo / "CHANGELOG.md").write_text("## 1.8.26（120）\n", encoding="utf-8")
        (repo / "README.md").write_text("当前正式包为 1.8.26（120）\n", encoding="utf-8")
        result = _run(script)
        self.assertNotEqual(0, result.returncode)

    def test_formal_patch_version_passes_when_formal_docs_match(self) -> None:
        result = _run(self._repo("1.8.31+124"))
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("1.8.31+124", result.stdout)

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

    def test_marked_patch_requires_every_formal_document_even_with_allow_dev(self) -> None:
        for path, expected in (
            ("CHANGELOG.md", "Changelog missing"),
            ("README.md", "README mismatch"),
            ("docs/guides/安装与使用.md", "Install guide mismatch"),
        ):
            with self.subTest(path=path):
                repo, script = _make_repo("1.92.4+135", newline="\r\n")
                self.temp_dirs.append(repo)
                pubspec = script.parents[1] / "pubspec.yaml"
                with pubspec.open("a", encoding="utf-8", newline="") as stream:
                    stream.write("# formal-release: 1.92.4+135\r\n")
                self.assertEqual(0, _run(script, "--allow-dev").returncode)
                (repo / path).unlink()
                result = _run(script, "--allow-dev")
                self.assertEqual(1, result.returncode)
                self.assertIn(expected, result.stderr)

    def test_mismatched_explicit_marker_is_rejected(self) -> None:
        script = self._repo("1.92.4+135")
        with (script.parents[1] / "pubspec.yaml").open("a", encoding="utf-8") as stream:
            stream.write("# formal-release: 1.92.5+136\n")
        result = _run(script, "--allow-dev")
        self.assertEqual(1, result.returncode)
        self.assertIn("Formal release marker", result.stderr)

    def test_dev_version_with_allow_dev_passes_when_formal_docs_stay_on_last_release(self) -> None:
        script = self._repo("1.92.1+133", formal_version="1.92.0+132")
        allowed = _run(script, "--allow-dev")
        self.assertEqual(0, allowed.returncode, allowed.stderr)
        self.assertIn("1.92.1+133", allowed.stdout)

        strict = _run(script)
        self.assertNotEqual(0, strict.returncode)

    def test_formal_zero_patch_requires_docs_even_with_allow_dev(self) -> None:
        script = self._repo("1.93.0+134", formal_version="1.92.0+132")
        result = _run(script, "--allow-dev")
        self.assertNotEqual(0, result.returncode)

    def test_tag_option_validates_tag_identity_and_strict_formal_docs(self) -> None:
        formal_script = self._repo("1.92.0+132")
        ok = _run(formal_script, "--tag", "v1.92.0")
        self.assertEqual(0, ok.returncode, ok.stderr)
        self.assertIn("1.92.0+132", ok.stdout)

        mismatch = _run(formal_script, "--tag", "v1.93.0")
        self.assertEqual(1, mismatch.returncode)
        self.assertIn("Tag mismatch", mismatch.stderr)

        unfrozen_hotfix = self._repo("1.92.1+133", formal_version="1.92.0+132")
        strict_fail = _run(unfrozen_hotfix, "--tag", "v1.92.1")
        self.assertNotEqual(0, strict_fail.returncode)

        frozen_hotfix = self._repo("1.92.1+133")
        strict_ok = _run(frozen_hotfix, "--tag", "v1.92.1")
        self.assertEqual(0, strict_ok.returncode, strict_ok.stderr)

        conflict = _run(frozen_hotfix, "--tag", "v1.92.1", "--allow-dev")
        self.assertNotEqual(0, conflict.returncode)

    def test_flutter_checks_workflow_metadata_gate_contract(self) -> None:
        workflow = (
            Path(__file__).resolve().parents[1]
            / ".github"
            / "workflows"
            / "flutter-checks.yml"
        ).read_text(encoding="utf-8")
        self.assertIn("python3 tool/check_release_metadata.py --tag", workflow)
        self.assertIn("python3 tool/check_release_metadata.py --allow-dev", workflow)
        self.assertIn("github.event.before", workflow)
        self.assertIn('tool/check_changed_format.py --base "$format_base"', workflow)
        self.assertNotIn(
            'GITHUB_EVENT_NAME" == workflow_dispatch && "$GITHUB_REF" == refs/heads/dev',
            workflow,
        )


if __name__ == "__main__":
    unittest.main()
