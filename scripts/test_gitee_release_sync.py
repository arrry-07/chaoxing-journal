#!/usr/bin/env python3
"""Offline tests for the Gitee release synchronization helpers."""

from __future__ import annotations

from dataclasses import replace
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock
import zipfile

import gitee_release_sync as sync


def artifact(
    version: str,
    code: int,
    *,
    tag: str | None = None,
) -> sync.ReleaseArtifact:
    version_tag = tag or f"v{version}"
    return sync.ReleaseArtifact(
        tag=version_tag,
        version_name=version,
        version_code=code,
        apk_name=f"chaoxing-journal-{version}.apk",
        size=1000 + code,
        sha256=f"{code:064x}",
        notes=f"Release {version}",
        github_release_url=(
            "https://github.com/arrry-07/chaoxing-journal/releases/tag/"
            f"{version_tag}"
        ),
    )


class VersionSelectionTests(unittest.TestCase):
    def test_manual_selects_highest_version_then_code(self) -> None:
        releases = [
            artifact("1.7.4", 56),
            artifact("1.7.52", 59),
            artifact("1.7.5", 57),
        ]

        selected = sync.choose_manual_release(releases)

        self.assertEqual(selected.version_name, "1.7.52")
        self.assertEqual(selected.version_code, 59)

    def test_identical_manual_release_keeps_current_manifest_identity(self) -> None:
        current = replace(artifact("1.7.52", 59), github_release_url="")
        downloaded = artifact("1.7.52", 59)

        selected = sync.choose_effective_manual_release(
            current,
            [downloaded],
        )

        self.assertIs(selected, current)

    def test_same_major_minor_patch_does_not_replace_stable(self) -> None:
        stable = artifact("1.7.4", 56)

        selected = sync.choose_stable_release(stable, artifact("1.7.52", 59))

        self.assertEqual(selected, stable)

    def test_higher_minor_release_replaces_stable(self) -> None:
        stable = artifact("1.7.4", 56)
        candidate = artifact("1.8.0", 60)

        selected = sync.choose_stable_release(stable, candidate)

        self.assertEqual(selected, candidate)


class ManifestTests(unittest.TestCase):
    def test_manifest_uses_gitee_primary_and_github_backup(self) -> None:
        release = artifact("1.7.52", 59)

        manifest = sync.build_manifest(
            release,
            gitee_repository="arrry-07/chaoxing-journal-updates",
            github_repository="arrry-07/chaoxing-journal",
        )

        self.assertEqual(
            manifest["apkUrl"],
            "https://gitee.com/arrry-07/chaoxing-journal-updates/"
            "releases/download/v1.7.52/chaoxing-journal-1.7.52.apk",
        )
        self.assertEqual(
            manifest["backupApkUrl"],
            "https://github.com/arrry-07/chaoxing-journal/"
            "releases/download/v1.7.52/chaoxing-journal-1.7.52.apk",
        )
        self.assertEqual(manifest["versionCode"], 59)
        self.assertEqual(manifest["versionName"], "1.7.52")
        self.assertEqual(manifest["size"], 1059)
        self.assertEqual(manifest["sha256"], f"{59:064x}")
        self.assertEqual(
            manifest["applicationId"],
            "com.example.studyassistant.journal",
        )

    def test_checksum_must_match_the_official_apk_name(self) -> None:
        expected = "a" * 64
        text = (
            f"{expected}  chaoxing-journal-1.7.52.apk\n"
            f"{'b' * 64}  unrelated.apk\n"
        )

        value = sync.parse_checksum(
            text, "chaoxing-journal-1.7.52.apk"
        )

        self.assertEqual(value, expected)
        with self.assertRaises(ValueError):
            sync.parse_checksum(text, "missing.apk")

    def test_existing_manifest_must_have_a_canonical_managed_tag(self) -> None:
        release = artifact("1.7.52", 59)
        value = sync.build_manifest(
            release,
            gitee_repository="arrry-07/chaoxing-journal-updates",
            github_repository="arrry-07/chaoxing-journal",
        )

        parsed = sync.manifest_artifact(value)

        self.assertEqual(parsed.tag, "v1.7.52")
        invalid = dict(value)
        invalid["versionName"] = "1.7-beta"
        with self.assertRaises(sync.SyncError):
            sync.manifest_artifact(invalid)


class RetentionTests(unittest.TestCase):
    def test_retention_keeps_stable_manual_and_newest_third_release(self) -> None:
        keep = sync.select_retained_tags(
            ["v1.7.4", "v1.7.5", "v1.7.51", "v1.7.52"],
            stable_tag="v1.7.4",
            manual_tag="v1.7.52",
            limit=3,
        )

        self.assertEqual(keep, {"v1.7.4", "v1.7.51", "v1.7.52"})

    def test_retention_rejects_limits_outside_three_to_five(self) -> None:
        for limit in (0, 2, 6):
            with self.subTest(limit=limit):
                with self.assertRaises(ValueError):
                    sync.select_retained_tags(
                        ["v1.7.4"],
                        stable_tag="v1.7.4",
                        manual_tag="v1.7.4",
                        limit=limit,
                    )

    def test_retention_requires_both_protected_tags(self) -> None:
        with self.assertRaises(ValueError):
            sync.select_retained_tags(
                ["v1.7.4", "v1.7.52"],
                stable_tag="v1.8.0",
                manual_tag="v1.7.52",
                limit=3,
            )

    def test_pruning_deletes_only_unprotected_managed_apk_releases(self) -> None:
        class FakeGitee:
            def __init__(self) -> None:
                self.deleted: list[int] = []
                self.releases = [
                    sync.GiteeRelease(
                        release_id=index,
                        tag=tag,
                        assets=(
                            {"name": f"chaoxing-journal-{tag[1:]}.apk"},
                        ),
                    )
                    for index, tag in enumerate(
                        ("v1.7.4", "v1.7.5", "v1.7.52", "v1.7.53"),
                        start=1,
                    )
                ]

            def list_releases(self) -> list[sync.GiteeRelease]:
                return list(self.releases)

            def delete_release(self, release: sync.GiteeRelease) -> None:
                self.deleted.append(release.release_id)

        gitee = FakeGitee()

        deleted = sync.prune_gitee_releases(
            gitee,  # type: ignore[arg-type]
            stable_tag="v1.7.4",
            manual_tag="v1.7.53",
            limit=3,
        )

        self.assertEqual(gitee.deleted, [2])
        self.assertEqual(deleted, ["v1.7.5"])

    def test_upload_waits_for_eventual_gitee_asset_visibility(self) -> None:
        release = artifact("1.7.52", 59)

        class FakeGitee:
            def __init__(self) -> None:
                self.calls = 0
                self.uploads = 0

            def find_release(self, tag: str) -> sync.GiteeRelease:
                self.calls += 1
                assets = ()
                if self.calls >= 3:
                    assets = ({"name": release.apk_name},)
                return sync.GiteeRelease(
                    release_id=7,
                    tag=tag,
                    assets=assets,
                )

            def upload_apk(
                self,
                _release: sync.GiteeRelease,
                _apk_path: Path,
            ) -> None:
                self.uploads += 1

        gitee = FakeGitee()
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.object(sync, "_download_public_apk"), mock.patch.object(
                sync.time, "sleep"
            ) as sleep:
                ensured = sync.ensure_gitee_release(
                    gitee,  # type: ignore[arg-type]
                    mock.sentinel.client,  # type: ignore[arg-type]
                    release,
                    apk_path=Path(directory) / release.apk_name,
                    work_dir=Path(directory),
                )

        self.assertEqual(ensured.tag, "v1.7.52")
        self.assertEqual(gitee.uploads, 1)
        sleep.assert_called()


class SafetyTests(unittest.TestCase):
    def test_unknown_or_prerelease_versions_are_rejected(self) -> None:
        for tag in ("release-1.7.52", "v1.7-beta", "v1.7.052"):
            with self.subTest(tag=tag):
                self.assertFalse(sync.is_managed_tag(tag))
        for version in ("1.7", "1.7-beta", "1.7.052"):
            with self.subTest(version=version):
                with self.assertRaises(ValueError):
                    sync.version_tuple(version)

    def test_error_redaction_never_returns_the_token(self) -> None:
        token = "secret-token-value"
        message = f"request failed: Bearer {token}"

        redacted = sync.redact_secret(message, token)

        self.assertNotIn(token, redacted)
        self.assertIn("[REDACTED]", redacted)

    def test_android_tool_output_is_decoded_as_utf8_on_windows(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "test.apk"
            with zipfile.ZipFile(apk, "w") as archive:
                archive.writestr("AndroidManifest.xml", b"manifest")
            results = [
                subprocess.CompletedProcess(
                    [],
                    0,
                    (
                        "package: name='com.example.studyassistant.journal' "
                        "versionCode='59' versionName='1.7.52'\n"
                    ),
                    "",
                ),
                subprocess.CompletedProcess(
                    [],
                    0,
                    (
                        "Signer #1 certificate SHA-256 digest: "
                        f"{sync.SIGNER_SHA256}\n"
                    ),
                    "",
                ),
            ]
            with mock.patch.object(
                sync.subprocess, "run", side_effect=results
            ) as run:
                identity = sync.inspect_apk(
                    apk,
                    aapt=Path("aapt"),
                    apksigner=Path("apksigner"),
                )

        self.assertEqual(identity["versionCode"], 59)
        for call in run.call_args_list:
            self.assertEqual(call.kwargs["encoding"], "utf-8")
            self.assertEqual(call.kwargs["errors"], "replace")

    def test_apksigner_certificate_is_read_from_stderr(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "test.apk"
            with zipfile.ZipFile(apk, "w") as archive:
                archive.writestr("AndroidManifest.xml", b"manifest")
            results = [
                subprocess.CompletedProcess(
                    [],
                    0,
                    (
                        "package: name='com.example.studyassistant.journal' "
                        "versionCode='56' versionName='1.7.4'\n"
                    ),
                    "",
                ),
                subprocess.CompletedProcess(
                    [],
                    0,
                    "",
                    (
                        "Signer #1 certificate SHA-256 digest: "
                        f"{sync.SIGNER_SHA256}\n"
                    ),
                ),
            ]
            with mock.patch.object(
                sync.subprocess, "run", side_effect=results
            ):
                identity = sync.inspect_apk(
                    apk,
                    aapt=Path("aapt"),
                    apksigner=Path("apksigner"),
                )

        self.assertEqual(identity["versionCode"], 56)


if __name__ == "__main__":
    unittest.main()
