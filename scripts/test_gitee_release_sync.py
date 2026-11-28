#!/usr/bin/env python3
"""Offline tests for the Gitee release synchronization helpers."""

from __future__ import annotations

import base64
from dataclasses import replace
import hashlib
import io
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
    def test_two_digit_patch_keeps_tag_and_stable_identity(self) -> None:
        stable = artifact("1.8.0", 67)
        patch = artifact("1.8.01", 68)
        self.assertEqual(sync.version_tuple(patch.version_name), (1, 8, 1))
        self.assertEqual(sync.tag_tuple(patch.tag), (1, 8, 1))
        self.assertEqual(sync.version_from_tag(patch.tag), "1.8.01")
        self.assertIs(sync.choose_manual_release([stable, patch]), patch)
        self.assertIs(sync.choose_stable_release(stable, patch), stable)

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

        self.assertEqual(
            sync.choose_stable_release(stable, candidate),
            stable,
        )
        self.assertEqual(
            sync.choose_stable_release(stable, candidate, promote_stable=True),
            candidate,
        )

    def test_promote_stable_accepts_same_minor_hotfix(self) -> None:
        stable = artifact("1.90.0", 130)
        hotfix = artifact("1.90.1", 131)

        self.assertEqual(
            sync.choose_stable_release(stable, hotfix, promote_stable=True),
            hotfix,
        )

    def test_highest_public_release_wins_even_when_latest_flag_is_elsewhere(
        self,
    ) -> None:
        selected = sync.select_latest_stable_release(
            [
                {
                    "tag_name": "v1.7.54",
                    "draft": False,
                    "prerelease": False,
                },
                {
                    "tag_name": "v1.7.55",
                    "draft": False,
                    "prerelease": False,
                },
                {
                    "tag_name": "v1.7.56",
                    "draft": True,
                    "prerelease": False,
                },
                {
                    "tag_name": "v1.8.0",
                    "draft": False,
                    "prerelease": True,
                },
                {
                    "tag_name": "release-1.9.0",
                    "draft": False,
                    "prerelease": False,
                },
            ]
        )

        self.assertEqual(selected["tag_name"], "v1.7.55")


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

    def test_same_version_notes_refresh_uses_lower_previous(self) -> None:
        current = artifact("1.7.52", 59)
        target = sync.with_gitee_release_notes(
            current,
            sync.GiteeRelease(
                release_id=7,
                tag=current.tag,
                assets=({"name": current.apk_name},),
                body="更新后的 Gitee 说明",
            ),
        )
        releases = [
            artifact("1.7.4", 56),
            artifact("1.7.5", 57),
            current,
        ]

        previous = sync.choose_previous_manual(
            target,
            current_manual=current,
            artifacts=releases,
            current_stable=releases[0],
        )

        self.assertEqual(previous.tag, "v1.7.5")

    def test_upload_missing_creates_release_uploads_apk_and_verifies_download(
        self,
    ) -> None:
        release = artifact("1.93.0", 136)
        calls: list[str] = []

        class FakeGitee:
            def __init__(self) -> None:
                self.created = False

            def find_release(self, tag: str) -> sync.GiteeRelease | None:
                if not self.created:
                    return None
                return sync.GiteeRelease(
                    release_id=99,
                    tag=tag,
                    assets=({"name": release.apk_name},),
                    body=release.notes,
                )

            def create_release(
                self, item: sync.ReleaseArtifact
            ) -> sync.GiteeRelease:
                calls.append(f"create:{item.tag}")
                self.created = True
                return sync.GiteeRelease(release_id=99, tag=item.tag, assets=())

            def upload_apk(
                self, gitee_release: sync.GiteeRelease, apk_path: Path
            ) -> None:
                calls.append(f"upload:{gitee_release.release_id}:{apk_path.name}")

        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / release.apk_name
            apk.write_bytes(b"apk-bytes")
            with mock.patch.object(sync, "_download_public_apk") as download:
                verified = sync.verify_gitee_release(
                    FakeGitee(),  # type: ignore[arg-type]
                    mock.sentinel.client,  # type: ignore[arg-type]
                    release,
                    full_download=True,
                    work_dir=Path(directory),
                    upload_missing=True,
                    apk_path=apk,
                )

        self.assertEqual(
            calls,
            ["create:v1.93.0", f"upload:99:{release.apk_name}"],
        )
        self.assertEqual(verified.release_id, 99)
        download.assert_called_once()

    def test_upload_missing_skips_idempotently_when_matching_apk_exists(
        self,
    ) -> None:
        release = artifact("1.93.0", 136)
        upload_called = False

        class FakeGitee:
            def find_release(self, tag: str) -> sync.GiteeRelease:
                return sync.GiteeRelease(
                    release_id=99,
                    tag=tag,
                    assets=({"name": release.apk_name},),
                )

            def upload_apk(self, *_args: object) -> None:
                nonlocal upload_called
                upload_called = True

        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / release.apk_name
            apk.write_bytes(b"apk-bytes")
            with mock.patch.object(sync, "_download_public_apk") as download:
                sync.verify_gitee_release(
                    FakeGitee(),  # type: ignore[arg-type]
                    mock.sentinel.client,  # type: ignore[arg-type]
                    release,
                    full_download=True,
                    work_dir=Path(directory),
                    upload_missing=True,
                    apk_path=apk,
                )

        self.assertFalse(upload_called)
        download.assert_called_once()

    def test_upload_missing_blocks_wrong_or_multiple_apk_assets(self) -> None:
        release = artifact("1.93.0", 136)

        class WrongAssetGitee:
            def find_release(self, tag: str) -> sync.GiteeRelease:
                return sync.GiteeRelease(
                    release_id=99,
                    tag=tag,
                    assets=({"name": "wrong.apk"},),
                )

        class MultiAssetGitee:
            def find_release(self, tag: str) -> sync.GiteeRelease:
                return sync.GiteeRelease(
                    release_id=99,
                    tag=tag,
                    assets=(
                        {"name": release.apk_name},
                        {"name": "extra.apk"},
                    ),
                )

        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / release.apk_name
            apk.write_bytes(b"apk-bytes")
            with self.assertRaisesRegex(
                sync.SyncError, "Gitee release APK identity did not match"
            ):
                sync.verify_gitee_release(
                    WrongAssetGitee(),  # type: ignore[arg-type]
                    mock.sentinel.client,  # type: ignore[arg-type]
                    release,
                    full_download=True,
                    work_dir=Path(directory),
                    upload_missing=True,
                    apk_path=apk,
                )
            with self.assertRaisesRegex(
                sync.SyncError, "Gitee release contained multiple APK assets"
            ):
                sync.verify_gitee_release(
                    MultiAssetGitee(),  # type: ignore[arg-type]
                    mock.sentinel.client,  # type: ignore[arg-type]
                    release,
                    full_download=True,
                    work_dir=Path(directory),
                    upload_missing=True,
                    apk_path=apk,
                )

    def test_gitee_upload_retries_transient_502_and_redacts_token(self) -> None:
        client = sync.HttpClient(github_token="", gitee_token="super-secret-token")
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "test.apk"
            apk.write_bytes(b"apk")
            outcomes = [
                subprocess.CompletedProcess([], 22, "bad gateway\n502 0 0", ""),
                subprocess.CompletedProcess([], 0, '{"id": 42}\n201 3 100', ""),
            ]
            with mock.patch.object(
                sync.shutil, "which", return_value="/usr/bin/curl"
            ), mock.patch.object(
                sync.subprocess, "run", side_effect=outcomes
            ) as run, mock.patch.object(sync.time, "sleep") as sleep:
                result = client.gitee_upload(
                    "/repos/owner/repo/releases/1/attach_files",
                    file_path=apk,
                )

        self.assertEqual(result, {"id": 42})
        self.assertEqual(run.call_count, 2)
        sleep.assert_called_once()

    def _verify_gitee_timeout_retry(self, *, uploaded_despite_timeout: bool) -> None:
        apk_bytes = b"verified synthetic APK"
        release = replace(
            artifact("1.93.0", 136),
            size=len(apk_bytes),
            sha256=hashlib.sha256(apk_bytes).hexdigest(),
        )
        client = sync.HttpClient(github_token="", gitee_token="mock-token")
        gitee = sync.GiteeReleaseClient(client)
        empty = sync.GiteeRelease(99, release.tag, ())
        with_apk = replace(empty, assets=({"name": release.apk_name},))
        retry_lookup = with_apk if uploaded_despite_timeout else empty
        public_url = sync.canonical_gitee_apk_url(
            "arrry-07/chaoxing-journal-updates", release
        )
        public_response = mock.MagicMock(
            status=200, headers={"Content-Length": str(release.size)}
        )
        public_response.__enter__.return_value = public_response
        public_response.geturl.return_value = public_url
        public_response.read.side_effect = io.BytesIO(apk_bytes).read

        with tempfile.TemporaryDirectory() as directory:
            work_dir = Path(directory)
            apk = work_dir / release.apk_name
            apk.write_bytes(apk_bytes)
            with (
                mock.patch.object(
                    gitee, "find_release", side_effect=[empty, retry_lookup, with_apk]
                ) as find,
                mock.patch.object(sync.shutil, "which", return_value="/usr/bin/curl"),
                mock.patch.object(
                    sync.subprocess,
                    "run",
                    side_effect=[
                        subprocess.TimeoutExpired("curl", 20),
                        subprocess.CompletedProcess([], 0, '{"id": 42}\n201 21 100', ""),
                    ],
                ) as run,
                mock.patch.object(sync.time, "sleep"),
                mock.patch.object(
                    sync.urllib.request, "urlopen", return_value=public_response
                ) as download,
            ):
                verified = sync.verify_gitee_release(
                    gitee,
                    client,
                    release,
                    full_download=False,
                    work_dir=work_dir,
                    upload_missing=True,
                    apk_path=apk,
                )
            self.assertEqual(verified, with_apk)
            self.assertEqual(run.call_count, 1 if uploaded_despite_timeout else 2)
            lookups = 2 if uploaded_despite_timeout else 3
            self.assertEqual(find.call_args_list, [mock.call(release.tag)] * lookups)
            download.assert_called_once()
            public_request = download.call_args.args[0]
            self.assertEqual(public_request.full_url, public_url)
            self.assertIsNone(public_request.get_header("Authorization"))
            self.assertEqual(
                (work_dir / "gitee-download" / apk.name).read_bytes(), apk_bytes
            )

    def test_upload_timeout_with_existing_attachment_skips_retry_and_verifies_download(self) -> None:
        self._verify_gitee_timeout_retry(uploaded_despite_timeout=True)

    def test_upload_timeout_without_attachment_retries_and_verifies_download(self) -> None:
        self._verify_gitee_timeout_retry(uploaded_despite_timeout=False)

    def test_prune_allows_unmirrored_github_only_stable_release(self) -> None:
        class FakeGitee:
            def __init__(self) -> None:
                self.deleted: list[str] = []

            def list_releases(self) -> list[sync.GiteeRelease]:
                return [
                    sync.GiteeRelease(
                        1, "v1.93.0", ({"name": "chaoxing-journal-1.93.0.apk"},)
                    ),
                    sync.GiteeRelease(
                        2, "v1.90.0", ({"name": "chaoxing-journal-1.90.0.apk"},)
                    ),
                    sync.GiteeRelease(
                        3, "v1.8.28", ({"name": "chaoxing-journal-1.8.28.apk"},)
                    ),
                    sync.GiteeRelease(
                        4, "v1.8.20", ({"name": "chaoxing-journal-1.8.20.apk"},)
                    ),
                ]

            def delete_release(self, release: sync.GiteeRelease) -> None:
                self.deleted.append(release.tag)

        gitee = FakeGitee()
        deleted = sync.prune_gitee_releases(
            gitee,  # type: ignore[arg-type]
            stable_tag="v1.92.0",
            manual_tag="v1.93.0",
            limit=3,
            require_stable=False,
        )
        self.assertEqual(deleted, ["v1.8.20"])
        self.assertEqual(gitee.deleted, ["v1.8.20"])

    def test_gitee_upload_retries_http_000_connection_failure(self) -> None:
        client = sync.HttpClient(github_token="", gitee_token="secret-token")
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "test.apk"
            apk.write_bytes(b"apk")
            outcomes = [
                subprocess.CompletedProcess([], 35, "\n000 0 0", "ssl error"),
                subprocess.CompletedProcess([], 0, '{"id": 7}\n201 3 100', ""),
            ]
            with mock.patch.object(
                sync.shutil, "which", return_value="/usr/bin/curl"
            ), mock.patch.object(
                sync.subprocess, "run", side_effect=outcomes
            ) as run, mock.patch.object(sync.time, "sleep") as sleep:
                result = client.gitee_upload(
                    "/repos/owner/repo/releases/1/attach_files",
                    file_path=apk,
                )
        self.assertEqual(result, {"id": 7})
        self.assertEqual(run.call_count, 2)
        sleep.assert_called_once()

    def test_gitee_upload_checks_attachment_after_http_201_response_timeout(self) -> None:
        client = sync.HttpClient(github_token="", gitee_token="synthetic")
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / "test.apk"
            apk.write_bytes(b"apk")
            for visible in (True, False):
                with self.subTest(visible=visible), mock.patch.object(
                    sync.shutil, "which", return_value="/usr/bin/curl"
                ), mock.patch.object(
                    sync.subprocess,
                    "run",
                    return_value=subprocess.CompletedProcess([], 28, "\n201 3 100", "timeout"),
                ) as run:
                    check = mock.Mock(return_value=visible)
                    arguments = dict(file_path=apk, already_uploaded=check)
                    endpoint = "/repos/owner/repo/releases/1/attach_files"
                    if visible:
                        self.assertIsNone(client.gitee_upload(endpoint, **arguments))
                    else:
                        with self.assertRaises(sync.SyncError):
                            client.gitee_upload(endpoint, **arguments)
                    check.assert_called_once_with()
                    run.assert_called_once()

    def test_upload_missing_does_not_double_post_when_list_lags(self) -> None:
        release = artifact("1.93.0", 136)
        uploads: list[str] = []

        class LaggingGitee:
            def __init__(self) -> None:
                self.created = False

            def find_release(self, tag: str) -> sync.GiteeRelease | None:
                if not self.created:
                    return None
                # Simulate eventual consistency lag where assets is still empty
                return sync.GiteeRelease(release_id=99, tag=tag, assets=())

            def create_release(
                self, item: sync.ReleaseArtifact
            ) -> sync.GiteeRelease:
                self.created = True
                return sync.GiteeRelease(release_id=99, tag=item.tag, assets=())

            def upload_apk(
                self, gitee_release: sync.GiteeRelease, apk_path: Path
            ) -> None:
                uploads.append(f"{gitee_release.release_id}:{apk_path.name}")

        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / release.apk_name
            apk.write_bytes(b"apk-bytes")
            with mock.patch.object(sync, "_download_public_apk") as download:
                sync.verify_gitee_release(
                    LaggingGitee(),  # type: ignore[arg-type]
                    mock.sentinel.client,  # type: ignore[arg-type]
                    release,
                    full_download=True,
                    work_dir=Path(directory),
                    upload_missing=True,
                    apk_path=apk,
                )
        self.assertEqual(uploads, [f"99:{release.apk_name}"])
        download.assert_called_once()

    def test_verify_gitee_artifacts_downloads_both_stable_and_manual_when_requested(
        self,
    ) -> None:
        releases = [
            artifact("1.92.0", 132),
            artifact("1.93.0", 136),
        ]

        class FakeGitee:
            def find_release(self, tag: str) -> sync.GiteeRelease:
                rel = next(item for item in releases if item.tag == tag)
                return sync.GiteeRelease(
                    release_id=7,
                    tag=tag,
                    assets=({"name": rel.apk_name},),
                )

        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.object(sync, "_download_public_apk") as download:
                sync.verify_gitee_artifacts(
                    FakeGitee(),  # type: ignore[arg-type]
                    mock.sentinel.client,  # type: ignore[arg-type]
                    releases,
                    latest_tag="v1.93.0",
                    work_dir=Path(directory),
                    full_download_tags={"v1.92.0", "v1.93.0"},
                )
        downloaded = sorted(call.args[1].tag for call in download.call_args_list)
        self.assertEqual(downloaded, ["v1.92.0", "v1.93.0"])

    def test_same_release_identity_ignores_notes_whitespace_differences(
        self,
    ) -> None:
        a = artifact("1.93.0", 136)
        b = sync.replace(a, notes=a.notes + "\n")
        self.assertTrue(sync._same_release_identity(a, b))


class IndexTests(unittest.TestCase):
    def test_unmirrored_index_uses_github_primary_without_backup(self) -> None:
        release = artifact("1.7.55", 62)

        manifest = sync.build_manifest(
            release,
            gitee_repository="arrry-07/chaoxing-journal-updates",
            github_repository="arrry-07/chaoxing-journal",
            gitee_verified=False,
        )

        self.assertEqual(
            manifest["apkUrl"],
            "https://github.com/arrry-07/chaoxing-journal/"
            "releases/download/v1.7.55/chaoxing-journal-1.7.55.apk",
        )
        self.assertNotIn("backupApkUrl", manifest)

    def test_verified_mirror_keeps_gitee_primary_and_github_backup(self) -> None:
        release = artifact("1.7.55", 62)
        current = sync.build_manifest(
            release,
            gitee_repository="arrry-07/chaoxing-journal-updates",
            github_repository="arrry-07/chaoxing-journal",
        )

        manifest = sync.build_index_manifest(
            release,
            existing_manifests=(current,),
            gitee_repository="arrry-07/chaoxing-journal-updates",
            github_repository="arrry-07/chaoxing-journal",
        )

        self.assertEqual(manifest, current)

    def test_index_metadata_reads_version_and_checksum_without_apk(self) -> None:
        release_name = "1.7.55"
        tag = f"v{release_name}"
        version_code = 62
        sha = "a" * 64
        apk_name = f"chaoxing-journal-{release_name}.apk"
        release_value = {
            "tag_name": tag,
            "html_url": (
                "https://github.com/arrry-07/chaoxing-journal/"
                f"releases/tag/{tag}"
            ),
            "body": "Release notes",
            "draft": False,
            "prerelease": False,
            "assets": [
                {
                    "name": apk_name,
                    "browser_download_url": (
                        "https://github.com/arrry-07/chaoxing-journal/"
                        f"releases/download/{tag}/{apk_name}"
                    ),
                    "size": 12345,
                    "digest": f"sha256:{sha}",
                },
                {
                    "name": "SHA256SUMS.txt",
                    "browser_download_url": (
                        "https://github.com/arrry-07/chaoxing-journal/"
                        f"releases/download/{tag}/SHA256SUMS.txt"
                    ),
                },
            ],
        }
        pubspec = f"name: study_assistant_mobile\nversion: {release_name}+{version_code}\n"

        class FakeClient:
            _github_token = "token"

            def github_json(self, path: str) -> dict:
                if "/contents/" in path:
                    return {
                        "encoding": "base64",
                        "content": base64.b64encode(pubspec.encode()).decode(),
                    }
                return release_value

            def public_text(self, _url: str, **_kwargs: object) -> str:
                return f"{sha}  {apk_name}\n"

            def download(self, *_args: object, **_kwargs: object) -> None:
                raise AssertionError("index mode must not download APK bytes")

        with tempfile.TemporaryDirectory() as directory:
            source = sync.GitHubReleaseSource(
                FakeClient(),  # type: ignore[arg-type]
                work_dir=Path(directory),
            )
            indexed, raw = source.index_metadata(tag)

        self.assertEqual(indexed.version_name, release_name)
        self.assertEqual(indexed.version_code, version_code)
        self.assertEqual(indexed.sha256, sha)
        self.assertEqual(indexed.size, 12345)
        self.assertEqual(raw["tag_name"], tag)

    def test_index_rejects_checksum_or_version_mismatch(self) -> None:
        for failure in ("checksum", "version"):
            with self.subTest(failure=failure):
                release_name = "1.7.55"
                tag = f"v{release_name}"
                sha = "a" * 64
                apk_name = f"chaoxing-journal-{release_name}.apk"
                release_value = {
                    "tag_name": tag,
                    "draft": False,
                    "prerelease": False,
                    "assets": [
                        {
                            "name": apk_name,
                            "browser_download_url": (
                                "https://github.com/arrry-07/chaoxing-journal/"
                                f"releases/download/{tag}/{apk_name}"
                            ),
                            "size": 12345,
                            "digest": f"sha256:{sha}",
                        },
                        {
                            "name": "SHA256SUMS.txt",
                            "browser_download_url": (
                                "https://github.com/arrry-07/chaoxing-journal/"
                                f"releases/download/{tag}/SHA256SUMS.txt"
                            ),
                        },
                    ],
                }
                version_name = "1.7.54" if failure == "version" else release_name
                pubspec = f"version: {version_name}+62\n"

                class FakeClient:
                    _github_token = "token"

                    def github_json(self, path: str) -> dict:
                        if "/contents/" in path:
                            return {
                                "encoding": "base64",
                                "content": base64.b64encode(
                                    pubspec.encode()
                                ).decode(),
                            }
                        return release_value

                    def public_text(self, _url: str, **_kwargs: object) -> str:
                        value = "b" * 64 if failure == "checksum" else sha
                        return f"{value}  {apk_name}\n"

                    def download(self, *_args: object, **_kwargs: object) -> None:
                        raise AssertionError("index mode must not download APK bytes")

                with tempfile.TemporaryDirectory() as directory:
                    source = sync.GitHubReleaseSource(
                        FakeClient(),  # type: ignore[arg-type]
                        work_dir=Path(directory),
                    )
                    with self.assertRaises(sync.SyncError):
                        source.index_metadata(tag)

    def test_index_sync_updates_manual_only_for_patch_and_is_idempotent(
        self,
    ) -> None:
        stable = sync.build_manifest(
            artifact("1.7.4", 56),
            gitee_repository="arrry-07/chaoxing-journal-updates",
            github_repository="arrry-07/chaoxing-journal",
        )
        manual = sync.build_manifest(
            artifact("1.7.52", 59),
            gitee_repository="arrry-07/chaoxing-journal-updates",
            github_repository="arrry-07/chaoxing-journal",
        )
        candidate = artifact("1.7.55", 62)

        class FakeGitHub:
            def index_metadata(self, tag: str | None) -> tuple:
                self.tag = tag
                return candidate, {"tag_name": "v1.7.55"}

        github = FakeGitHub()
        args = sync.build_parser().parse_args(
            [
                "--mode",
                "index",
                "--work-dir",
                tempfile.mkdtemp(prefix="journal-index-test-"),
            ]
        )
        published: list[tuple[dict, dict]] = []

        def publish(**kwargs: object) -> bool:
            published.append(
                (kwargs["stable_manifest"], kwargs["manual_manifest"])  # type: ignore[index]
            )
            return True

        with (
            mock.patch.object(
                sync, "publish_manifests", side_effect=publish
            ),
            mock.patch.object(sync, "verify_published_manifests"),
            mock.patch.object(sync, "prune_gitee_releases") as prune,
        ):
            result = sync.synchronize_index(
                args,
                client=mock.sentinel.client,  # type: ignore[arg-type]
                github=github,  # type: ignore[arg-type]
                work_dir=Path(args.work_dir),
                current_stable_json=stable,
                current_manual_json=manual,
                tags=["v1.7.55"],
            )
            first_stable, first_manual = published[-1]
            result_again = sync.synchronize_index(
                args,
                client=mock.sentinel.client,  # type: ignore[arg-type]
                github=github,  # type: ignore[arg-type]
                work_dir=Path(args.work_dir),
                current_stable_json=first_stable,
                current_manual_json=first_manual,
                tags=["v1.7.55"],
            )

        self.assertEqual(result, 0)
        self.assertEqual(result_again, 0)
        self.assertEqual(github.tag, "v1.7.55")
        self.assertEqual(first_stable, stable)
        self.assertEqual(first_manual["versionName"], "1.7.55")
        self.assertEqual(first_manual["apkUrl"], candidate_github_url(candidate))
        self.assertNotIn("backupApkUrl", first_manual)
        self.assertEqual(published[-1], (first_stable, first_manual))
        prune.assert_not_called()

    def test_batch_switches_same_version_github_index_to_verified_mirror(
        self,
    ) -> None:
        candidate = artifact("1.7.55", 62)
        indexed = sync.build_manifest(
            candidate,
            gitee_repository="arrry-07/chaoxing-journal-updates",
            github_repository="arrry-07/chaoxing-journal",
            gitee_verified=False,
        )

        class FakeGitHub:
            def download_and_verify(
                self, _tag: str | None, **_kwargs: object
            ) -> tuple:
                return candidate, {"tag_name": "v1.7.55"}

        args = sync.build_parser().parse_args(
            [
                "--mode",
                "latest",
                "--work-dir",
                tempfile.mkdtemp(prefix="journal-batch-test-"),
            ]
        )
        published: list[tuple[dict, dict]] = []

        def publish(**kwargs: object) -> bool:
            published.append(
                (
                    kwargs["stable_manifest"],  # type: ignore[index]
                    kwargs["manual_manifest"],  # type: ignore[index]
                )
            )
            return True

        release = sync.GiteeRelease(
            release_id=7,
            tag=candidate.tag,
            assets=({"name": candidate.apk_name},),
        )
        with (
            mock.patch.dict("os.environ", {"GITEE_TOKEN": "token"}),
            mock.patch.object(
                sync,
                "read_public_manifests",
                return_value=(indexed, indexed),
            ),
            mock.patch.object(
                sync,
                "GitHubReleaseSource",
                return_value=FakeGitHub(),
            ),
            mock.patch.object(
                sync,
                "find_android_tool",
                return_value=Path("android-tool"),
            ),
            mock.patch.object(
                sync.GiteeReleaseClient,
                "verify_access",
                return_value="arrry-07",
            ),
            mock.patch.object(
                sync,
                "verify_gitee_artifacts",
                return_value={candidate.tag: release},
            ),
            mock.patch.object(
                sync,
                "publish_manifests",
                side_effect=publish,
            ),
            mock.patch.object(sync, "verify_published_manifests"),
            mock.patch.object(
                sync,
                "prune_gitee_releases",
                return_value=[],
            ),
        ):
            result = sync.synchronize(args)

        self.assertEqual(result, 0)
        stable_manifest, manual_manifest = published[-1]
        for value in (stable_manifest, manual_manifest):
            self.assertEqual(
                value["apkUrl"],
                sync.canonical_gitee_apk_url(
                    "arrry-07/chaoxing-journal-updates",
                    candidate,
                ),
            )
            self.assertEqual(
                value["backupApkUrl"],
                sync.canonical_github_apk_url(
                    "arrry-07/chaoxing-journal",
                    candidate,
                ),
            )

    def test_index_synchronize_skips_android_tools(self) -> None:
        stable = sync.build_manifest(
            artifact("1.7.4", 56),
            gitee_repository="arrry-07/chaoxing-journal-updates",
            github_repository="arrry-07/chaoxing-journal",
        )
        candidate = artifact("1.7.55", 62)

        class FakeGitHub:
            def index_metadata(self, _tag: str | None) -> tuple:
                return candidate, {}

        args = sync.build_parser().parse_args(["--mode", "index", "--dry-run"])
        with (
            mock.patch.object(
                sync,
                "read_public_manifests",
                return_value=(stable, None),
            ),
            mock.patch.object(
                sync,
                "GitHubReleaseSource",
                return_value=FakeGitHub(),
            ),
            mock.patch.object(sync, "find_android_tool") as android_tool,
            mock.patch.object(sync, "publish_manifests") as publish,
        ):
            result = sync.synchronize(args)

        self.assertEqual(result, 0)
        android_tool.assert_not_called()
        publish.assert_not_called()


def candidate_github_url(release: sync.ReleaseArtifact) -> str:
    return (
        "https://github.com/arrry-07/chaoxing-journal/releases/download/"
        f"{release.tag}/{release.apk_name}"
    )


class SafetyTests(unittest.TestCase):
    def test_two_digit_patch_is_narrowly_supported(self) -> None:
        for patch in ("01", "09"):
            self.assertTrue(sync.is_managed_tag("v1.8." + patch))
        for patch in ("00", "001", "052", "01-beta"):
            self.assertFalse(sync.is_managed_tag("v1.8." + patch))
            with self.assertRaises(ValueError):
                sync.version_tuple("1.8." + patch)

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

    def test_seed_promote_stable_fetches_retained_manual_when_seed_tags_older(
        self,
    ) -> None:
        v174 = artifact("1.7.4", 56)
        v180 = artifact("1.8.0", 67)
        v174_gh_apk = (
            "https://github.com/arrry-07/chaoxing-journal/releases/download/"
            f"{v174.tag}/{v174.apk_name}"
        )
        v180_gh_apk = (
            "https://github.com/arrry-07/chaoxing-journal/releases/download/"
            f"{v180.tag}/{v180.apk_name}"
        )
        current_stable_json = {
            "versionCode": 56,
            "versionName": "1.7.4",
            "applicationId": sync.APPLICATION_ID,
            "apkUrl": (
                "https://gitee.com/arrry-07/chaoxing-journal-updates/"
                "releases/download/v1.7.4/chaoxing-journal-1.7.4.apk"
            ),
            "backupApkUrl": v174_gh_apk,
            "sha256": v174.sha256,
            "size": v174.size,
            "notes": "1.7.4",
        }
        current_manual_json = {
            "versionCode": 67,
            "versionName": "1.8.0",
            "applicationId": sync.APPLICATION_ID,
            "apkUrl": (
                "https://gitee.com/arrry-07/chaoxing-journal-updates/"
                "releases/download/v1.8.0/chaoxing-journal-1.8.0.apk"
            ),
            "backupApkUrl": v180_gh_apk,
            "sha256": v180.sha256,
            "size": v180.size,
            "notes": "1.8.0",
        }

        fetched_tags: list[str] = []

        class FakeGitHub:
            def __init__(self, _client: object, *, work_dir: Path, **_kw: object) -> None:
                self.work_dir = work_dir

            def download_and_verify(
                self, tag: str | None, **_kw: object
            ) -> tuple[sync.ReleaseArtifact, dict[str, object]]:
                assert tag is not None
                fetched_tags.append(tag)
                art = v180 if tag == "v1.8.0" else v174
                apk_dir = self.work_dir / art.tag
                apk_dir.mkdir(parents=True, exist_ok=True)
                (apk_dir / art.apk_name).write_bytes(b"PK\x03\x04fake")
                return art, {"tag_name": art.tag, "body": art.notes}

        class FakeGitee:
            def __init__(self, *_a: object, **_kw: object) -> None:
                pass

            def verify_access(self) -> None:
                pass

            def list_releases(self) -> list[dict[str, object]]:
                return []

        published: dict[str, object] = {}

        def fake_generate(art: sync.ReleaseArtifact, *, channel: str, **_kw: object) -> dict[str, object]:
            return {
                "versionCode": art.version_code,
                "versionName": art.version_name,
                "applicationId": sync.APPLICATION_ID,
                "apkUrl": (
                    f"https://gitee.com/arrry-07/chaoxing-journal-updates/"
                    f"releases/download/{art.tag}/{art.apk_name}"
                ),
                "backupApkUrl": (
                    "https://github.com/arrry-07/chaoxing-journal/releases/"
                    f"download/{art.tag}/{art.apk_name}"
                ),
                "sha256": art.sha256,
                "size": art.size,
                "notes": f"{channel}:{art.version_name}",
            }

        def fake_publish(**kwargs: object) -> bool:
            published.update(kwargs)
            return True

        with (
            mock.patch.dict("os.environ", {"GITEE_TOKEN": "fake-token"}),
            mock.patch.object(
                sync,
                "read_public_manifests",
                return_value=(current_stable_json, current_manual_json),
            ),
            mock.patch.object(sync, "GitHubReleaseSource", FakeGitHub),
            mock.patch.object(sync, "GiteeReleaseClient", FakeGitee),
            mock.patch.object(
                sync,
                "verify_gitee_artifacts",
                return_value={
                    "v1.7.4": mock.Mock(body="1.7.4"),
                    "v1.8.0": mock.Mock(body="1.8.0"),
                },
            ),
            mock.patch.object(sync, "generate_manifest", side_effect=fake_generate),
            mock.patch.object(sync, "publish_manifests", side_effect=fake_publish),
            mock.patch.object(sync, "verify_published_manifests", return_value=None),
            mock.patch.object(sync, "prune_gitee_releases", return_value=[]),
        ):
            rc = sync.main(
                [
                    "--mode",
                    "seed",
                    "--tags",
                    "v1.7.4",
                    "--promote-stable",
                    "--aapt",
                    "aapt",
                    "--apksigner",
                    "apksigner",
                ]
            )

        self.assertEqual(rc, 0)
        self.assertEqual(fetched_tags, ["v1.7.4", "v1.8.0"])
        self.assertEqual(published["stable_manifest"]["versionName"], "1.8.0")


if __name__ == "__main__":
    unittest.main()
