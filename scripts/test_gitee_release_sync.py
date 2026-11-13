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

    def test_historical_gitee_asset_check_skips_full_download(self) -> None:
        release = artifact("1.7.52", 59)

        class FakeGitee:
            def find_release(self, tag: str) -> sync.GiteeRelease:
                return sync.GiteeRelease(
                    release_id=7,
                    tag=tag,
                    assets=({"name": release.apk_name},),
                )

        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.object(sync, "_download_public_apk") as download:
                checked = sync.verify_gitee_release(
                    FakeGitee(),  # type: ignore[arg-type]
                    mock.sentinel.client,  # type: ignore[arg-type]
                    release,
                    full_download=False,
                    work_dir=Path(directory),
                )

        self.assertEqual(checked.tag, "v1.7.52")
        download.assert_not_called()

    def test_latest_gitee_asset_check_downloads_full_apk(self) -> None:
        release = artifact("1.7.52", 59)

        class FakeGitee:
            def find_release(self, tag: str) -> sync.GiteeRelease:
                return sync.GiteeRelease(
                    release_id=7,
                    tag=tag,
                    assets=({"name": release.apk_name},),
                )

        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.object(sync, "_download_public_apk") as download:
                sync.verify_gitee_release(
                    FakeGitee(),  # type: ignore[arg-type]
                    mock.sentinel.client,  # type: ignore[arg-type]
                    release,
                    full_download=True,
                    work_dir=Path(directory),
                )

        download.assert_called_once()

    def test_seed_verification_fully_downloads_only_latest(self) -> None:
        releases = [
            artifact("1.7.4", 56),
            artifact("1.7.5", 57),
            artifact("1.7.52", 59),
        ]

        class FakeGitee:
            def find_release(self, tag: str) -> sync.GiteeRelease:
                release = next(item for item in releases if item.tag == tag)
                return sync.GiteeRelease(
                    release_id=7,
                    tag=tag,
                    assets=({"name": release.apk_name},),
                )

        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.object(sync, "_download_public_apk") as download:
                sync.verify_gitee_artifacts(
                    FakeGitee(),  # type: ignore[arg-type]
                    mock.sentinel.client,  # type: ignore[arg-type]
                    releases,
                    latest_tag="v1.7.52",
                    work_dir=Path(directory),
                )

        downloaded = [
            call.args[1].tag for call in download.call_args_list
        ]
        self.assertEqual(downloaded, ["v1.7.52"])

    def test_missing_gitee_release_requires_web_upload(self) -> None:
        release = artifact("1.7.52", 59)

        class FakeGitee:
            def find_release(self, _tag: str) -> None:
                return None

        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(
                sync.SyncError,
                "must be created and uploaded in the Gitee web backend",
            ):
                sync.verify_gitee_release(
                    FakeGitee(),  # type: ignore[arg-type]
                    mock.sentinel.client,  # type: ignore[arg-type]
                    release,
                    full_download=False,
                    work_dir=Path(directory),
                )

    def test_gitee_attachment_name_must_match(self) -> None:
        release = artifact("1.7.52", 59)

        class FakeGitee:
            def find_release(self, tag: str) -> sync.GiteeRelease:
                return sync.GiteeRelease(
                    release_id=7,
                    tag=tag,
                    assets=({"name": "wrong.apk"},),
                )

        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(
                sync.SyncError,
                "Gitee release APK identity did not match",
            ):
                sync.verify_gitee_release(
                    FakeGitee(),  # type: ignore[arg-type]
                    mock.sentinel.client,  # type: ignore[arg-type]
                    release,
                    full_download=False,
                    work_dir=Path(directory),
                )

    def test_gitee_release_body_overrides_manual_notes(self) -> None:
        release = artifact("1.7.52", 59)
        gitee_release = sync.GiteeRelease(
            release_id=7,
            tag=release.tag,
            assets=({"name": release.apk_name},),
            body="Gitee 验证式发布说明",
        )

        updated = sync.with_gitee_release_notes(release, gitee_release)

        self.assertEqual(updated.notes, "Gitee 验证式发布说明")
        self.assertEqual(updated.sha256, release.sha256)


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

    def test_gitee_upload_streams_file_with_extended_timeout(self) -> None:
        client = sync.HttpClient(github_token="", gitee_token="token")
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "test.apk"
            apk.write_bytes(b"apk")
            with mock.patch.object(
                client,
                "_request",
                return_value=(201, b"{}", "application/json"),
            ) as request, mock.patch.object(
                sync.shutil,
                "which",
                return_value="/usr/bin/curl",
            ), mock.patch.object(
                sync.subprocess,
                "run",
                return_value=subprocess.CompletedProcess(
                    [],
                    0,
                    '{"id": 1}\n201',
                    "",
                ),
            ) as run:
                result = client.gitee_upload(
                    "/repos/owner/repo/releases/1/attach_files",
                    file_path=apk,
                )

        command = run.call_args.args[0]
        self.assertEqual(result, {"id": 1})
        self.assertIn("--max-time", command)
        self.assertEqual(command[command.index("--max-time") + 1], "600")
        file_form = next(item for item in command if item.startswith("file=@"))
        self.assertIn(str(apk), file_form)
        request.assert_not_called()

    def test_gitee_upload_keeps_token_out_of_command_arguments(self) -> None:
        client = sync.HttpClient(github_token="", gitee_token="secret-token")
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "test.apk"
            apk.write_bytes(b"apk")
            with mock.patch.object(
                client,
                "_request",
                return_value=(201, b"{}", "application/json"),
            ), mock.patch.object(
                sync.shutil,
                "which",
                return_value="/usr/bin/curl",
            ), mock.patch.object(
                sync.subprocess,
                "run",
                return_value=subprocess.CompletedProcess(
                    [],
                    0,
                    '{"id": 1}\n201',
                    "",
                ),
            ) as run:
                client.gitee_upload(
                    "/repos/owner/repo/releases/1/attach_files",
                    file_path=apk,
                )

        command = run.call_args.args[0]
        config = run.call_args.kwargs["input"]
        self.assertNotIn("secret-token", " ".join(command))
        self.assertIn("access_token=secret-token", config)

    def test_gitee_upload_uses_compatible_http_transport(self) -> None:
        client = sync.HttpClient(github_token="", gitee_token="token")
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "test.apk"
            apk.write_bytes(b"apk")
            with mock.patch.object(
                sync.shutil,
                "which",
                return_value="/usr/bin/curl",
            ), mock.patch.object(
                sync.subprocess,
                "run",
                return_value=subprocess.CompletedProcess(
                    [],
                    0,
                    '{"id": 1}\n201',
                    "",
                ),
            ) as run:
                client.gitee_upload(
                    "/repos/owner/repo/releases/1/attach_files",
                    file_path=apk,
                )

        command = run.call_args.args[0]
        self.assertIn("--ipv4", command)
        self.assertIn("--http1.1", command)
        self.assertIn("Expect:", command)

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
