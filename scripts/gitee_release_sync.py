#!/usr/bin/env python3
"""Synchronize verified GitHub releases to the public Gitee update mirror.

The script intentionally uses only the Python standard library. It never writes
the Gitee token to a file, URL, command line, or log.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from typing import Any, Iterable
import urllib.error
import urllib.parse
import urllib.request
import zipfile


GITHUB_OWNER = "arrry-07"
GITHUB_REPO = "chaoxing-journal"
GITEE_OWNER = "arrry-07"
GITEE_REPO = "chaoxing-journal-updates"
GITHUB_API = "https://api.github.com"
GITEE_API = "https://gitee.com/api/v5"
GITEE_REPOSITORY_URL = "https://gitee.com/arrry-07/chaoxing-journal-updates"
GITEE_RAW_BASE = (
    "https://raw.giteeusercontent.com/"
    "arrry-07/chaoxing-journal-updates/raw/master"
)
APPLICATION_ID = "com.example.studyassistant.journal"
SIGNER_SHA256 = (
    "d36a571510e046dd196d7384f849f82b4fcff05ce3affb334765d5c752265d8a"
)
MAX_DOWNLOAD_BYTES = 256 * 1024 * 1024
MAX_JSON_BYTES = 2 * 1024 * 1024
USER_AGENT = "chaoxing-journal-gitee-sync/1.0"
TAG_PATTERN = re.compile(r"^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
RAW_VERSION_PATTERN = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")


class SyncError(RuntimeError):
    """A safe, user-facing synchronization error."""


@dataclass(frozen=True)
class ReleaseArtifact:
    tag: str
    version_name: str
    version_code: int
    apk_name: str
    size: int
    sha256: str
    notes: str
    github_release_url: str


@dataclass(frozen=True)
class GiteeRelease:
    release_id: int
    tag: str
    assets: tuple[dict[str, Any], ...]


def version_tuple(value: str) -> tuple[int, int, int]:
    match = RAW_VERSION_PATTERN.fullmatch(value)
    if match is None:
        raise ValueError("Version must contain exactly three canonical numbers.")
    return tuple(int(part) for part in match.groups())


def tag_tuple(tag: str) -> tuple[int, int, int]:
    match = TAG_PATTERN.fullmatch(tag)
    if match is None:
        raise ValueError("Tag must match vX.Y.Z.")
    return tuple(int(part) for part in match.groups())


def version_from_tag(tag: str) -> str:
    tag_tuple(tag)
    return tag[1:]


def is_managed_tag(tag: str) -> bool:
    return TAG_PATTERN.fullmatch(tag) is not None


def parse_tags(value: str) -> list[str]:
    tags = [part.strip() for part in re.split(r"[\s,]+", value) if part.strip()]
    if not tags:
        return []
    if len(set(tags)) != len(tags):
        raise ValueError("Seed tags must not contain duplicates.")
    for tag in tags:
        tag_tuple(tag)
    return sorted(tags, key=tag_tuple)


def _release_key(release: ReleaseArtifact) -> tuple[tuple[int, int, int], int]:
    return version_tuple(release.version_name), release.version_code


def choose_manual_release(releases: Iterable[ReleaseArtifact]) -> ReleaseArtifact:
    values = list(releases)
    if not values:
        raise ValueError("At least one release is required.")
    return max(values, key=_release_key)


def choose_stable_release(
    current: ReleaseArtifact,
    candidate: ReleaseArtifact,
) -> ReleaseArtifact:
    current_version = version_tuple(current.version_name)
    candidate_version = version_tuple(candidate.version_name)
    if candidate_version[:2] > current_version[:2]:
        return candidate
    return current


def canonical_github_apk_url(
    repository: str,
    release: ReleaseArtifact,
) -> str:
    return (
        f"https://github.com/{repository}/releases/download/"
        f"{release.tag}/{release.apk_name}"
    )


def canonical_gitee_apk_url(
    repository: str,
    release: ReleaseArtifact,
) -> str:
    return (
        f"https://gitee.com/{repository}/releases/download/"
        f"{release.tag}/{release.apk_name}"
    )


def build_manifest(
    release: ReleaseArtifact,
    *,
    gitee_repository: str,
    github_repository: str,
) -> dict[str, Any]:
    return {
        "versionCode": release.version_code,
        "versionName": release.version_name,
        "apkUrl": canonical_gitee_apk_url(gitee_repository, release),
        "backupApkUrl": canonical_github_apk_url(github_repository, release),
        "sha256": release.sha256,
        "applicationId": APPLICATION_ID,
        "notes": release.notes,
        "size": release.size,
    }


def parse_checksum(text: str, apk_name: str) -> str:
    matches: list[str] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        match = re.fullmatch(r"([0-9a-fA-F]{64})\s+\*?(.+)", line)
        if match is None:
            raise ValueError("SHA256SUMS contains a malformed line.")
        if match.group(2).strip() == apk_name:
            matches.append(match.group(1).lower())
    if len(matches) != 1:
        raise ValueError("SHA256SUMS must contain exactly one matching APK.")
    return matches[0]


def select_retained_tags(
    tags: Iterable[str],
    *,
    stable_tag: str,
    manual_tag: str,
    limit: int,
) -> set[str]:
    if limit < 3 or limit > 5:
        raise ValueError("Retention limit must be between 3 and 5.")
    tag_tuple(stable_tag)
    tag_tuple(manual_tag)
    managed = sorted(
        {tag for tag in tags if is_managed_tag(tag)},
        key=tag_tuple,
        reverse=True,
    )
    if stable_tag not in managed or manual_tag not in managed:
        raise ValueError("Stable and manual releases must both exist.")
    keep = {stable_tag, manual_tag}
    for tag in managed:
        if len(keep) >= limit:
            break
        keep.add(tag)
    return keep


def redact_secret(value: str, secret: str) -> str:
    if not secret:
        return value
    return value.replace(secret, "[REDACTED]")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while True:
            chunk = stream.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def safe_io_error(url: str, status: int | None = None) -> SyncError:
    parsed = urllib.parse.urlsplit(url)
    safe_url = f"{parsed.scheme}://{parsed.netloc}{parsed.path}"
    if status is None:
        return SyncError(f"Could not read {safe_url}.")
    return SyncError(f"HTTP {status} from {safe_url}.")


class HttpClient:
    def __init__(self, *, github_token: str, gitee_token: str) -> None:
        self._github_token = github_token
        self._gitee_token = gitee_token

    def _headers(self, token: str, extra: dict[str, str] | None = None) -> dict[str, str]:
        headers = {
            "Accept": "application/json",
            "User-Agent": USER_AGENT,
        }
        if token:
            headers["Authorization"] = f"Bearer {token}"
        if extra:
            headers.update(extra)
        return headers

    def _request(
        self,
        method: str,
        url: str,
        *,
        token: str = "",
        data: bytes | None = None,
        headers: dict[str, str] | None = None,
        max_bytes: int = MAX_JSON_BYTES,
        allow_not_found: bool = False,
    ) -> tuple[int, bytes, str]:
        request = urllib.request.Request(
            url,
            data=data,
            method=method,
            headers=self._headers(token, headers),
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                status = response.status
                final_url = response.geturl()
                if urllib.parse.urlsplit(final_url).scheme != "https":
                    raise SyncError("Network redirect downgraded from HTTPS.")
                content_length = response.headers.get("Content-Length")
                if content_length is not None:
                    try:
                        if int(content_length) > max_bytes:
                            raise SyncError("Remote response exceeded the size limit.")
                    except ValueError:
                        raise SyncError("Remote response had an invalid size.")
                body = response.read(max_bytes + 1)
                if len(body) > max_bytes:
                    raise SyncError("Remote response exceeded the size limit.")
                return status, body, response.headers.get("Content-Type", "")
        except urllib.error.HTTPError as error:
            if allow_not_found and error.code == 404:
                return 404, b"", error.headers.get("Content-Type", "")
            raise safe_io_error(url, error.code) from None
        except urllib.error.URLError:
            raise safe_io_error(url) from None
        except TimeoutError:
            raise safe_io_error(url) from None

    def github_json(
        self,
        path: str,
        *,
        method: str = "GET",
        payload: dict[str, Any] | None = None,
    ) -> Any:
        body = None
        headers = None
        if payload is not None:
            body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            headers = {"Content-Type": "application/json"}
        _, response, _ = self._request(
            method,
            f"{GITHUB_API}{path}",
            token=self._github_token,
            data=body,
            headers=headers,
        )
        try:
            return json.loads(response.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise SyncError("GitHub returned invalid JSON.") from None

    def gitee_json(
        self,
        path: str,
        *,
        method: str = "GET",
        payload: dict[str, Any] | None = None,
        allow_not_found: bool = False,
    ) -> Any:
        body = None
        headers = None
        if payload is not None:
            body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            headers = {"Content-Type": "application/json"}
        status, response, _ = self._request(
            method,
            f"{GITEE_API}{path}",
            token=self._gitee_token,
            data=body,
            headers=headers,
            allow_not_found=allow_not_found,
        )
        if status == 404 or not response:
            return None
        try:
            return json.loads(response.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise SyncError("Gitee returned invalid JSON.") from None

    def gitee_upload(
        self,
        path: str,
        *,
        file_path: Path,
    ) -> Any:
        boundary = f"----journal-{secrets.token_hex(16)}"
        filename = file_path.name
        content_type = "application/vnd.android.package-archive"
        prefix = (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'
            f"Content-Type: {content_type}\r\n\r\n"
        ).encode("utf-8")
        suffix = f"\r\n--{boundary}--\r\n".encode("ascii")
        body = prefix + file_path.read_bytes() + suffix
        _, response, _ = self._request(
            "POST",
            f"{GITEE_API}{path}",
            token=self._gitee_token,
            data=body,
            headers={
                "Content-Type": f"multipart/form-data; boundary={boundary}",
            },
        )
        try:
            return json.loads(response.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise SyncError("Gitee returned invalid JSON after upload.") from None

    def download(
        self,
        url: str,
        destination: Path,
        *,
        token: str = "",
        expected_size: int | None = None,
        expected_sha256: str | None = None,
    ) -> tuple[int, str]:
        request = urllib.request.Request(
            url,
            headers=self._headers(token),
        )
        destination.parent.mkdir(parents=True, exist_ok=True)
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                if response.status != 200:
                    raise safe_io_error(url, response.status)
                if urllib.parse.urlsplit(response.geturl()).scheme != "https":
                    raise SyncError("Download redirect downgraded from HTTPS.")
                digest = hashlib.sha256()
                received = 0
                declared = response.headers.get("Content-Length")
                if declared is not None and int(declared) > MAX_DOWNLOAD_BYTES:
                    raise SyncError("APK exceeded the download size limit.")
                with destination.open("wb") as output:
                    while True:
                        chunk = response.read(1024 * 1024)
                        if not chunk:
                            break
                        received += len(chunk)
                        if received > MAX_DOWNLOAD_BYTES:
                            raise SyncError("APK exceeded the download size limit.")
                        output.write(chunk)
                        digest.update(chunk)
        except urllib.error.HTTPError as error:
            destination.unlink(missing_ok=True)
            raise safe_io_error(url, error.code) from None
        except (urllib.error.URLError, TimeoutError):
            destination.unlink(missing_ok=True)
            raise safe_io_error(url) from None
        except Exception:
            destination.unlink(missing_ok=True)
            raise
        actual_hash = digest.hexdigest()
        if expected_size is not None and received != expected_size:
            destination.unlink(missing_ok=True)
            raise SyncError("Downloaded APK size did not match the release.")
        if expected_sha256 is not None and actual_hash != expected_sha256.lower():
            destination.unlink(missing_ok=True)
            raise SyncError("Downloaded APK SHA-256 did not match the release.")
        return received, actual_hash

    def public_json(self, url: str) -> dict[str, Any] | None:
        status, body, _ = self._request(
            "GET",
            url,
            max_bytes=64 * 1024,
            allow_not_found=True,
        )
        if status == 404:
            return None
        try:
            value = json.loads(body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise SyncError("Published update manifest was not valid JSON.")
        if not isinstance(value, dict):
            raise SyncError("Published update manifest was not a JSON object.")
        return value


class GitHubReleaseSource:
    def __init__(
        self,
        client: HttpClient,
        *,
        repository: str = f"{GITHUB_OWNER}/{GITHUB_REPO}",
        work_dir: Path,
    ) -> None:
        self.client = client
        self.repository = repository
        self.work_dir = work_dir

    def metadata(self, tag: str | None) -> dict[str, Any]:
        endpoint = "/latest" if tag is None else f"/tags/{urllib.parse.quote(tag, safe='')}"
        value = self.client.github_json(
            f"/repos/{self.repository}/releases{endpoint}"
        )
        if not isinstance(value, dict):
            raise SyncError("GitHub release metadata was invalid.")
        if value.get("draft") is not False or value.get("prerelease") is not False:
            raise SyncError("Only public non-draft stable releases may be mirrored.")
        return value

    def download_and_verify(
        self,
        tag: str | None,
        *,
        aapt: Path,
        apksigner: Path,
    ) -> tuple[ReleaseArtifact, dict[str, Any]]:
        release = self.metadata(tag)
        release_tag = str(release.get("tag_name", ""))
        version_name = version_from_tag(release_tag)
        apk_name = f"chaoxing-journal-{version_name}.apk"
        assets = release.get("assets")
        if not isinstance(assets, list):
            raise SyncError("GitHub release assets were invalid.")
        apk_assets = [
            item
            for item in assets
            if isinstance(item, dict) and item.get("name") == apk_name
        ]
        checksum_assets = [
            item
            for item in assets
            if isinstance(item, dict) and item.get("name") == "SHA256SUMS.txt"
        ]
        if len(apk_assets) != 1 or len(checksum_assets) != 1:
            raise SyncError("GitHub release must contain one APK and SHA256SUMS.")
        apk_asset = apk_assets[0]
        checksum_asset = checksum_assets[0]
        digest_text = str(apk_asset.get("digest", ""))
        if not re.fullmatch(r"sha256:[0-9a-fA-F]{64}", digest_text):
            raise SyncError("GitHub APK digest was missing or invalid.")
        github_sha = digest_text[7:].lower()
        size = apk_asset.get("size")
        if not isinstance(size, int) or size <= 0 or size > MAX_DOWNLOAD_BYTES:
            raise SyncError("GitHub APK size was invalid.")
        apk_url = str(apk_asset.get("browser_download_url", ""))
        checksum_url = str(checksum_asset.get("browser_download_url", ""))
        expected_apk_url = (
            f"https://github.com/{self.repository}/releases/download/"
            f"{release_tag}/{apk_name}"
        )
        if apk_url != expected_apk_url:
            raise SyncError("GitHub APK URL did not match the official release route.")
        directory = self.work_dir / release_tag
        directory.mkdir(parents=True, exist_ok=True)
        apk_path = directory / apk_name
        checksum_path = directory / "SHA256SUMS.txt"
        self.client.download(
            apk_url,
            apk_path,
            token=self.client._github_token,
            expected_size=size,
            expected_sha256=github_sha,
        )
        self.client.download(
            checksum_url,
            checksum_path,
            token=self.client._github_token,
        )
        checksum = parse_checksum(
            checksum_path.read_text(encoding="utf-8"),
            apk_name,
        )
        if checksum != github_sha:
            raise SyncError("SHA256SUMS did not match the GitHub asset digest.")
        identity = inspect_apk(apk_path, aapt=aapt, apksigner=apksigner)
        if identity["versionName"] != version_name:
            raise SyncError("APK versionName did not match the GitHub release tag.")
        artifact = ReleaseArtifact(
            tag=release_tag,
            version_name=version_name,
            version_code=identity["versionCode"],
            apk_name=apk_name,
            size=size,
            sha256=github_sha,
            notes=str(release.get("body") or ""),
            github_release_url=str(release.get("html_url") or ""),
        )
        return artifact, release


class GiteeReleaseClient:
    def __init__(
        self,
        client: HttpClient,
        *,
        repository: str = f"{GITEE_OWNER}/{GITEE_REPO}",
    ) -> None:
        self.client = client
        self.repository = repository

    def verify_access(self) -> str:
        value = self.client.gitee_json("/user")
        if not isinstance(value, dict) or value.get("login") != GITEE_OWNER:
            raise SyncError("Gitee token does not belong to the repository owner.")
        return GITEE_OWNER

    def list_releases(self) -> list[GiteeRelease]:
        values: list[GiteeRelease] = []
        page = 1
        while True:
            response = self.client.gitee_json(
                f"/repos/{self.repository}/releases?per_page=100&page={page}"
            )
            if response is None:
                return values
            if not isinstance(response, list):
                raise SyncError("Gitee release list was invalid.")
            for item in response:
                if not isinstance(item, dict):
                    raise SyncError("Gitee release entry was invalid.")
                release_id = item.get("id")
                tag = item.get("tag_name")
                assets = item.get("assets")
                if not isinstance(release_id, int) or not isinstance(tag, str):
                    raise SyncError("Gitee release identity was invalid.")
                if assets is None:
                    assets = []
                if not isinstance(assets, list):
                    raise SyncError("Gitee release assets were invalid.")
                values.append(
                    GiteeRelease(
                        release_id=release_id,
                        tag=tag,
                        assets=tuple(
                            asset for asset in assets if isinstance(asset, dict)
                        ),
                    )
                )
            if len(response) < 100:
                break
            page += 1
        return values

    def find_release(self, tag: str) -> GiteeRelease | None:
        return next((item for item in self.list_releases() if item.tag == tag), None)

    def create_release(self, artifact: ReleaseArtifact) -> GiteeRelease:
        value = self.client.gitee_json(
            f"/repos/{self.repository}/releases",
            method="POST",
            payload={
                "tag_name": artifact.tag,
                "name": f"学习通课业手记 {artifact.version_name} ({artifact.version_code})",
                "body": artifact.notes,
                "target_commitish": "master",
                "prerelease": False,
            },
        )
        if not isinstance(value, dict) or not isinstance(value.get("id"), int):
            raise SyncError("Gitee did not return a valid release identity.")
        return GiteeRelease(
            release_id=value["id"],
            tag=artifact.tag,
            assets=(),
        )

    def upload_apk(self, release: GiteeRelease, apk_path: Path) -> None:
        value = self.client.gitee_upload(
            f"/repos/{self.repository}/releases/{release.release_id}/attach_files",
            file_path=apk_path,
        )
        if not isinstance(value, (dict, list)):
            raise SyncError("Gitee did not return an upload result.")

    def delete_release(self, release: GiteeRelease) -> None:
        self.client.gitee_json(
            f"/repos/{self.repository}/releases/{release.release_id}",
            method="DELETE",
        )


def inspect_apk(apk_path: Path, *, aapt: Path, apksigner: Path) -> dict[str, Any]:
    if not apk_path.is_file() or apk_path.suffix.lower() != ".apk":
        raise SyncError("APK path was invalid.")
    with zipfile.ZipFile(apk_path) as archive:
        if archive.testzip() is not None:
            raise SyncError("APK ZIP CRC validation failed.")
    result = subprocess.run(
        [str(aapt), "dump", "badging", str(apk_path)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=60,
        check=False,
    )
    if result.returncode != 0:
        raise SyncError("aapt rejected the APK.")
    identity = re.search(
        r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'",
        result.stdout,
    )
    if identity is None:
        raise SyncError("APK identity could not be parsed.")
    app_id, version_code_text, version_name = identity.groups()
    try:
        version_code = int(version_code_text)
    except ValueError:
        raise SyncError("APK versionCode was invalid.") from None
    if app_id != APPLICATION_ID or version_code <= 0:
        raise SyncError("APK applicationId or versionCode was invalid.")
    signature = subprocess.run(
        [str(apksigner), "verify", "--verbose", "--print-certs", str(apk_path)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=60,
        check=False,
    )
    if signature.returncode != 0:
        raise SyncError("APK signature verification failed.")
    certificate = re.search(
        r"Signer #1 certificate SHA-256 digest:\s*([0-9a-fA-F:]+)",
        signature.stdout,
    )
    if (
        certificate is None
        or certificate.group(1).replace(":", "").lower() != SIGNER_SHA256
    ):
        raise SyncError("APK signer did not match the registered certificate.")
    return {
        "applicationId": app_id,
        "versionCode": version_code,
        "versionName": version_name,
    }


def find_android_tool(name: str) -> Path:
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if not sdk:
        raise SyncError("ANDROID_HOME or ANDROID_SDK_ROOT is required.")
    root = Path(sdk) / "build-tools"
    if not root.is_dir():
        raise SyncError("Android build-tools were missing.")
    candidates: list[tuple[tuple[int, ...], Path]] = []
    for directory in root.iterdir():
        match = re.fullmatch(r"(\d+(?:\.\d+)+)", directory.name)
        if match is None or not directory.is_dir():
            continue
        executable = directory / (f"{name}.exe" if os.name == "nt" else name)
        if not executable.exists() and os.name == "nt":
            executable = directory / f"{name}.bat"
        if executable.is_file():
            candidates.append(
                (tuple(int(part) for part in match.group(1).split(".")), executable)
            )
    if not candidates:
        raise SyncError(f"Android tool {name} was not found.")
    return max(candidates, key=lambda item: item[0])[1]


def _run_manifest_script(arguments: list[str], *, work_dir: Path) -> dict[str, Any]:
    powershell = shutil.which("pwsh") or shutil.which("powershell")
    if powershell is None:
        raise SyncError("PowerShell is required to generate update manifests.")
    command = [
        powershell,
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(Path(__file__).with_name("update-manifest.ps1")),
        *arguments,
    ]
    result = subprocess.run(
        command,
        cwd=work_dir,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=180,
        check=False,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip().splitlines()
        message = detail[-1] if detail else "unknown PowerShell error"
        raise SyncError(f"Manifest generation failed: {message}")
    output = result.stdout.strip().splitlines()
    if not output or not output[-1].startswith("apk sha256"):
        raise SyncError("Manifest generator returned an unexpected result.")
    output_path = Path(arguments[arguments.index("-OutPath") + 1])
    try:
        value = json.loads(output_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        raise SyncError("Generated manifest was unreadable.") from None
    if not isinstance(value, dict):
        raise SyncError("Generated manifest was not a JSON object.")
    return value


def generate_manifest(
    artifact: ReleaseArtifact,
    *,
    channel: str,
    apk_path: Path,
    output_path: Path,
    evidence_path: Path | None,
    previous: ReleaseArtifact | None,
    aapt: Path,
    apksigner: Path,
    work_dir: Path,
    gitee_repository: str,
    github_repository: str,
) -> dict[str, Any]:
    arguments = [
        "-ApkPath",
        str(apk_path),
        "-VersionName",
        artifact.version_name,
        "-VersionCode",
        str(artifact.version_code),
        "-Channel",
        channel,
        "-ApkUrl",
        canonical_gitee_apk_url(gitee_repository, artifact),
        "-BackupApkUrl",
        canonical_github_apk_url(github_repository, artifact),
        "-Notes",
        artifact.notes,
        "-OutPath",
        str(output_path),
        "-AaptPath",
        str(aapt),
        "-ApkSignerPath",
        str(apksigner),
    ]
    if channel == "stable" and previous is None:
        if evidence_path is None:
            raise SyncError("Stable baseline requires GitHub release evidence.")
        arguments.extend(
            [
                "-InitializeStableBaseline",
                "-VerifiedReleaseEvidencePath",
                str(evidence_path),
                "-StableEntryPath",
                str(output_path),
            ]
        )
    else:
        if previous is None:
            raise SyncError("Previous release is required.")
        arguments.extend(
            [
                "-PreviousVersionName",
                previous.version_name,
                "-PreviousVersionCode",
                str(previous.version_code),
            ]
        )
    return _run_manifest_script(arguments, work_dir=work_dir)


def manifest_artifact(
    value: dict[str, Any],
) -> ReleaseArtifact:
    try:
        version_name = str(value["versionName"])
        version_tuple(version_name)
        version_code = int(value["versionCode"])
        apk_url = str(value["apkUrl"])
        size = int(value["size"])
        sha = str(value["sha256"]).lower()
    except (KeyError, TypeError, ValueError):
        raise SyncError("Existing Gitee manifest was invalid.") from None
    filename = Path(urllib.parse.urlsplit(apk_url).path).name
    if (
        not filename
        or size <= 0
        or not re.fullmatch(r"[0-9a-f]{64}", sha)
    ):
        raise SyncError("Existing Gitee manifest values were invalid.")
    return ReleaseArtifact(
        tag=f"v{version_name}",
        version_name=version_name,
        version_code=version_code,
        apk_name=filename,
        size=size,
        sha256=sha,
        notes=str(value.get("notes") or ""),
        github_release_url="",
    )


def read_public_manifests(
    client: HttpClient,
) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    stable = client.public_json(f"{GITEE_RAW_BASE}/update-stable.json")
    manual = client.public_json(f"{GITEE_RAW_BASE}/update-manual.json")
    return stable, manual


def _askpass_script(directory: Path) -> Path:
    path = directory / "gitee-askpass.sh"
    path.write_text(
        "#!/bin/sh\n"
        'case "$1" in\n'
        '  *Username*) printf "%s\\n" "$GITEE_USERNAME" ;;\n'
        '  *) printf "%s\\n" "$GITEE_TOKEN" ;;\n'
        "esac\n",
        encoding="utf-8",
    )
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return path


def _git(
    arguments: list[str],
    *,
    cwd: Path,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        ["git", *arguments],
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=180,
        check=False,
    )
    if result.returncode != 0:
        raise SyncError(f"Git command failed: git {arguments[0]}.")
    return result


def publish_manifests(
    *,
    work_dir: Path,
    stable_manifest: dict[str, Any],
    manual_manifest: dict[str, Any],
    repository: str,
    token: str,
) -> bool:
    checkout = work_dir / "gitee-repository"
    if checkout.exists():
        raise SyncError("Gitee checkout directory already exists.")
    repo_url = f"https://gitee.com/{repository}.git"
    _git(["clone", "--depth", "1", repo_url, str(checkout)], cwd=work_dir)
    stable_text = json.dumps(stable_manifest, ensure_ascii=False, separators=(",", ":"))
    manual_text = json.dumps(manual_manifest, ensure_ascii=False, separators=(",", ":"))
    (checkout / "update-stable.json").write_text(stable_text, encoding="utf-8")
    (checkout / "update-manual.json").write_text(manual_text, encoding="utf-8")
    (checkout / "README.md").write_text(
        render_readme(stable_manifest, manual_manifest),
        encoding="utf-8",
    )
    _git(["config", "user.name", "chaoxing-journal-sync"], cwd=checkout)
    _git(
        ["config", "user.email", "chaoxing-journal-sync@users.noreply.github.com"],
        cwd=checkout,
    )
    _git(
        [
            "add",
            "--",
            "README.md",
            "update-stable.json",
            "update-manual.json",
        ],
        cwd=checkout,
    )
    diff = subprocess.run(
        ["git", "diff", "--cached", "--quiet"],
        cwd=checkout,
        capture_output=True,
        timeout=60,
        check=False,
    )
    if diff.returncode == 0:
        return False
    if diff.returncode != 1:
        raise SyncError("Could not inspect pending Gitee manifest changes.")
    _git(["commit", "-m", "chore: sync update manifests"], cwd=checkout)
    askpass = _askpass_script(work_dir)
    env = os.environ.copy()
    env.update(
        {
            "GIT_ASKPASS": str(askpass),
            "GIT_TERMINAL_PROMPT": "0",
            "GITEE_USERNAME": GITEE_OWNER,
            "GITEE_TOKEN": token,
        }
    )
    _git(["push", "origin", "HEAD:master"], cwd=checkout, env=env)
    return True


def render_readme(
    stable_manifest: dict[str, Any],
    manual_manifest: dict[str, Any],
) -> str:
    stable = stable_manifest["versionName"]
    manual = manual_manifest["versionName"]
    return f"""# 学习通课业手记国内更新

本仓库公开学习通课业手记的国内更新清单和经过校验的 Android 安装包。

- stable：`{stable}`，只随主/次版本前进。
- manual：`{manual}`，指向最新正式补丁。
- 最多保留 3 个 APK Release；更早版本请前往 GitHub Releases。
- GitHub 是发布源和备用下载源，Gitee 是国内主下载源。

固定清单：

- {GITEE_RAW_BASE}/update-stable.json
- {GITEE_RAW_BASE}/update-manual.json

维护流程由 `arrry-07/chaoxing-journal` 的 GitHub Actions 每日执行。所有 APK
在发布清单前都经过大小、SHA-256、包名、版本和签名校验。
"""


def _download_public_apk(
    client: HttpClient,
    artifact: ReleaseArtifact,
    *,
    work_dir: Path,
) -> None:
    url = canonical_gitee_apk_url(f"{GITEE_OWNER}/{GITEE_REPO}", artifact)
    target = work_dir / "gitee-download" / artifact.apk_name
    client.download(
        url,
        target,
        expected_size=artifact.size,
        expected_sha256=artifact.sha256,
    )


def ensure_gitee_release(
    gitee: GiteeReleaseClient,
    client: HttpClient,
    artifact: ReleaseArtifact,
    *,
    apk_path: Path,
    work_dir: Path,
) -> GiteeRelease:
    release = gitee.find_release(artifact.tag)
    if release is None:
        release = gitee.create_release(artifact)
    uploaded = False
    apk_assets: list[dict[str, Any]] = []
    for attempt in range(31):
        apk_assets = [
            asset
            for asset in release.assets
            if isinstance(asset.get("name"), str)
            and str(asset["name"]).endswith(".apk")
        ]
        if len(apk_assets) > 1:
            raise SyncError("Gitee release contained multiple APK assets.")
        if apk_assets:
            break
        if not uploaded:
            gitee.upload_apk(release, apk_path)
            uploaded = True
        if attempt < 30:
            time.sleep(2)
        refreshed = gitee.find_release(artifact.tag)
        if refreshed is None:
            raise SyncError("Gitee release disappeared after upload.")
        release = refreshed
    if not apk_assets:
        raise SyncError("Gitee APK attachment did not become visible.")
    if len(apk_assets) != 1 or apk_assets[0].get("name") != artifact.apk_name:
        raise SyncError("Gitee release APK identity did not match.")
    _download_public_apk(client, artifact, work_dir=work_dir)
    return release


def verify_published_manifests(
    client: HttpClient,
    *,
    expected_stable: dict[str, Any],
    expected_manual: dict[str, Any],
    timeout_seconds: int = 300,
) -> None:
    deadline = time.monotonic() + timeout_seconds
    while True:
        cache_bust = secrets.token_hex(8)
        stable = client.public_json(
            f"{GITEE_RAW_BASE}/update-stable.json?sync={cache_bust}"
        )
        manual = client.public_json(
            f"{GITEE_RAW_BASE}/update-manual.json?sync={cache_bust}"
        )
        if stable == expected_stable and manual == expected_manual:
            return
        if time.monotonic() >= deadline:
            raise SyncError("Published Gitee manifests did not match after push.")
        time.sleep(10)


def prune_gitee_releases(
    gitee: GiteeReleaseClient,
    *,
    stable_tag: str,
    manual_tag: str,
    limit: int,
) -> list[str]:
    releases = gitee.list_releases()
    managed = [
        release
        for release in releases
        if is_managed_tag(release.tag)
        and any(
            isinstance(asset.get("name"), str)
            and str(asset["name"]).endswith(".apk")
            for asset in release.assets
        )
    ]
    tags = [release.tag for release in managed]
    keep = select_retained_tags(
        tags,
        stable_tag=stable_tag,
        manual_tag=manual_tag,
        limit=limit,
    )
    deleted: list[str] = []
    for release in managed:
        if release.tag in keep:
            continue
        gitee.delete_release(release)
        deleted.append(release.tag)
    return deleted


def _evidence(
    release: dict[str, Any],
    artifact: ReleaseArtifact,
    *,
    repository: str,
) -> dict[str, Any]:
    source = (
        f"https://api.github.com/repos/{repository}/releases/tags/"
        f"{urllib.parse.quote(artifact.tag, safe='')}"
    )
    return {
        "verified": True,
        "verifiedAtUtc": datetime.now(timezone.utc).isoformat(),
        "sourceUrl": source,
        "versionCode": artifact.version_code,
        "release": release,
    }


def synchronize(args: argparse.Namespace) -> int:
    if args.retention < 3 or args.retention > 5:
        raise SyncError("Retention must be between 3 and 5.")
    github_token = os.environ.get("GITHUB_TOKEN", "")
    gitee_token = os.environ.get("GITEE_TOKEN", "")
    if not gitee_token and not args.dry_run:
        raise SyncError("GITEE_TOKEN is required.")
    work_dir = Path(args.work_dir).resolve() if args.work_dir else Path(
        tempfile.mkdtemp(prefix="journal-gitee-")
    )
    work_dir.mkdir(parents=True, exist_ok=True)
    client = HttpClient(
        github_token=github_token,
        gitee_token=gitee_token,
    )
    github = GitHubReleaseSource(
        client,
        repository=args.github_repository,
        work_dir=work_dir,
    )
    gitee = GiteeReleaseClient(client, repository=args.gitee_repository)
    if not args.dry_run:
        gitee.verify_access()
    current_stable_json, current_manual_json = read_public_manifests(client)
    seed_tags = parse_tags(args.tags)
    if args.mode == "seed" and not seed_tags:
        raise SyncError("Seed mode requires comma-separated tags.")
    tags: list[str | None]
    if args.mode == "seed":
        tags = seed_tags
    else:
        tags = [None]
    aapt = Path(args.aapt) if args.aapt else find_android_tool("aapt")
    apksigner = Path(args.apksigner) if args.apksigner else find_android_tool(
        "apksigner"
    )
    artifacts: list[ReleaseArtifact] = []
    raw_releases: dict[str, dict[str, Any]] = {}
    for tag in tags:
        artifact, raw_release = github.download_and_verify(
            tag,
            aapt=aapt,
            apksigner=apksigner,
        )
        artifacts.append(artifact)
        raw_releases[artifact.tag] = raw_release
        if args.dry_run:
            continue
        apk_path = work_dir / artifact.tag / artifact.apk_name
        ensure_gitee_release(
            gitee,
            client,
            artifact,
            apk_path=apk_path,
            work_dir=work_dir,
        )
    current_stable = (
        manifest_artifact(current_stable_json)
        if current_stable_json is not None
        else None
    )
    current_manual = (
        manifest_artifact(current_manual_json)
        if current_manual_json is not None
        else None
    )
    target_manual = choose_manual_release(
        [*artifacts, *([current_manual] if current_manual is not None else [])]
    )
    if current_stable is None and args.mode == "seed":
        current_stable = min(artifacts, key=_release_key)
    if current_stable is None:
        raise SyncError("Stable manifest is missing; seed must run first.")
    target_stable = choose_stable_release(current_stable, target_manual)
    if args.dry_run:
        print(
            json.dumps(
                {
                    "mode": args.mode,
                    "stable": target_stable.version_name,
                    "manual": target_manual.version_name,
                    "retention": args.retention,
                },
                ensure_ascii=False,
            )
        )
        return 0

    generated_dir = work_dir / "manifests"
    generated_dir.mkdir(parents=True, exist_ok=True)
    stable_output = generated_dir / "update-stable.json"
    manual_output = generated_dir / "update-manual.json"
    if current_stable_json is None or target_stable != current_stable:
        raw = raw_releases[target_stable.tag]
        evidence_path = generated_dir / "stable-evidence.json"
        evidence_path.write_text(
            json.dumps(
                _evidence(raw, target_stable, repository=args.github_repository),
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )
        stable_manifest = generate_manifest(
            target_stable,
            channel="stable",
            apk_path=work_dir / target_stable.tag / target_stable.apk_name,
            output_path=stable_output,
            evidence_path=evidence_path,
            previous=None if current_stable_json is None else current_stable,
            aapt=aapt,
            apksigner=apksigner,
            work_dir=work_dir,
            gitee_repository=args.gitee_repository,
            github_repository=args.github_repository,
        )
    else:
        stable_manifest = current_stable_json

    if current_manual_json is not None and target_manual == current_manual:
        manual_manifest = current_manual_json
    else:
        previous = current_manual
        if previous is None:
            prior = [
                item
                for item in artifacts
                if item.version_code < target_manual.version_code
            ]
            if not prior:
                prior = [current_stable] if current_stable.version_code < target_manual.version_code else []
            if not prior:
                raise SyncError("No prior release was available for manual manifest.")
            previous = max(prior, key=_release_key)
        manual_manifest = generate_manifest(
            target_manual,
            channel="manual",
            apk_path=work_dir / target_manual.tag / target_manual.apk_name,
            output_path=manual_output,
            evidence_path=None,
            previous=previous,
            aapt=aapt,
            apksigner=apksigner,
            work_dir=work_dir,
            gitee_repository=args.gitee_repository,
            github_repository=args.github_repository,
        )
    changed = publish_manifests(
        work_dir=work_dir,
        stable_manifest=stable_manifest,
        manual_manifest=manual_manifest,
        repository=args.gitee_repository,
        token=gitee_token,
    )
    verify_published_manifests(
        client,
        expected_stable=stable_manifest,
        expected_manual=manual_manifest,
    )
    stable_tag = f"v{stable_manifest['versionName']}"
    manual_tag = f"v{manual_manifest['versionName']}"
    deleted = prune_gitee_releases(
        gitee,
        stable_tag=stable_tag,
        manual_tag=manual_tag,
        limit=args.retention,
    )
    print(
        json.dumps(
            {
                "changed": changed,
                "stable": stable_manifest["versionName"],
                "manual": manual_manifest["versionName"],
                "deleted": deleted,
            },
            ensure_ascii=False,
        )
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("daily", "seed"), default="daily")
    parser.add_argument("--tags", default="")
    parser.add_argument("--retention", type=int, default=3)
    parser.add_argument("--work-dir", default="")
    parser.add_argument("--github-repository", default=f"{GITHUB_OWNER}/{GITHUB_REPO}")
    parser.add_argument("--gitee-repository", default=f"{GITEE_OWNER}/{GITEE_REPO}")
    parser.add_argument("--aapt", default="")
    parser.add_argument("--apksigner", default="")
    parser.add_argument("--dry-run", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return synchronize(args)
    except (SyncError, ValueError) as error:
        token = os.environ.get("GITEE_TOKEN", "")
        print(f"ERROR: {redact_secret(str(error), token)}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
