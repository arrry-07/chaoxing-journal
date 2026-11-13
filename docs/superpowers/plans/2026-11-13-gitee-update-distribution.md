# Gitee Update Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver Gitee-first update manifests and APK downloads with GitHub fallback, automated daily cloud synchronization, a three-APK retention cap, and a verified `1.7.52+59` migration release.

**Architecture:** The Flutter client reads fixed Gitee JSON manifests, validates one shared update contract, falls back to GitHub only when the primary manifest fails, and retains the existing GitHub APK backup path. A standard-library Python job runs only in GitHub Actions to verify GitHub assets, publish Gitee Releases, atomically update manifests, verify anonymous downloads, and prune old releases.

**Tech Stack:** Flutter/Dart, Dio, PowerShell 5.1+, Python 3 standard library, Gitee API v5, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-13-gitee-update-distribution-design.md`

## Global Constraints

- Gitee repository: `arrry-07/chaoxing-journal-updates`.
- Gitee JSON host: `https://raw.giteeusercontent.com/arrry-07/chaoxing-journal-updates/raw/master/`.
- Stable stays `1.7.4+56`; manual becomes latest patch.
- Migration version: `1.7.52+59`.
- Gitee keeps at most 3 APK Releases.
- APK upload runs at most once per day from the scheduled GitHub Actions job.
- No APK transfer on the maintainer workstation.
- Token remains only in GitHub Secrets and runner environment.
- Reserved package typo `com.example.studystassistant.journal` is forbidden; exact package is `com.example.studyassistant.journal`.
- Signing certificate SHA-256: `d36a571510e046dd196d7384f849f82b4fcff05ce3affb334765d5c752265d8a`.
- Failed or unverified manifests must not be published.

## Review Focus

- A Gitee manifest outage must still discover a GitHub release without masking an invalid vehicle.
- A valid Gitee manifest that says the app is current must not trigger an unnecessary GitHub request.
- APK primary failure may use the GitHub backup only for transient failures; digest mismatch must stop.
- Re-running the daily job must not re-upload an unchanged APK or create an unbounded release history.
- Pruning must never delete the APK referenced by stable or manual.

### Task 1: Manifest Generator Baseline and Backup URLs

**Files:**
- Modify: `scripts/update-manifest.ps1`
- Modify: `scripts/test-update-manifest.ps1`

**Interfaces:**
- Consumes: verified APK path and an exact GitHub Release evidence JSON.
- Produces: `update-stable.json` and `update-manual.json` with `apkUrl`, `backupApkUrl`, size, SHA-256 and version identity.

- [ ] Add failing PowerShell tests for safe one-time `-InitializeStableBaseline`, rejection when stable exists, and GitHub backup URL preservation.
- [ ] Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-update-manifest.ps1` and confirm the new cases fail.
- [ ] Extend `update-manifest.ps1` with the baseline mode while retaining the existing offline preflight mode.
- [ ] Re-run the PowerShell suite and require all cases to pass.
- [ ] Commit the focused change.

### Task 2: Client Gitee Defaults and Manifest-Level Fallback

**Files:**
- Modify: `study_assistant-1.1.0/local_app/lib/src/services/app_update_service.dart`
- Modify: `study_assistant-1.1.0/local_app/test/update_manifest_test.dart`
- Modify: `study_assistant-1.1.0/local_app/test/app_update_service_test.dart`

**Interfaces:**
- Consumes: fixed Gitee stable/manual manifest URLs and existing `AppUpdateInfo.downloadUrls`.
- Produces: `checkConfigured` / `checkForStartup` that use Gitee first and automatic GitHub release fallback on manifest failure.

- [ ] Add failing tests for Gitee defaults, valid-manifest no-GitHub-request, network failure fallback, invalid-JSON fallback, cancellation no-fallback, and GitHub fallback APK digest validation.
- [ ] Run the focused tests and confirm RED.
- [ ] Implement manifest fallback without changing APK retry rules.
- [ ] Run focused tests, `dart analyze`, and update-related widget tests and require GREEN.
- [ ] Commit the client change.

### Task 3: Gitee Release Synchronizer

**Files:**
- Create: `scripts/gitee_release_sync.py`
- Create: `scripts/test_gitee_release_sync.py`

**Interfaces:**
- Consumes: `GITHUB_TOKEN`, `GITEE_TOKEN`, GitHub tags, verified APK and checksum assets.
- Produces: Gitee Releases, platform manifests, static Gitee README, and verbatim retention capped at 3.

- [ ] Add failing Python tests for version selection, release reuse/conflict, APK metadata verification, manifest JSON generation, protected retention, and secret-free HTTP errors.
- [ ] Run `python scripts/test_gitee_release_sync.py` and confirm RED.
- [ ] Implement the standard-library API and Git client logic with dry-run support.
- [ ] Re-run tests and a local dry-run with synthetic fixtures.
- [ ] Commit the synchronizer.

### Task 4: Daily Automation and Documentation

**Files:**
- Create: `.github/workflows/gitee-release-sync.yml`
- Modify: `.github/workflows/flutter-checks.yml`
- Modify: `docs/guides/更新渠道与国内分发.md`
- Create: `docs/reviews/2026-11-13-Gitee国内更新分发验收.md`

**Interfaces:**
- Consumes: successful synchronizer tests and `GITEE_TOKEN`.
- Produces: one scheduled daily workflow, manual seed/dispatch mode, and operational documentation.

- [ ] Add a failing workflow lint/static check for required schedule, dispatch inputs, permissions and secret references.
- [ ] Implement the workflow and CI test invocation.
- [ ] Document anonymous URLs, daily schedule, seed command, retention, and VPN/TUN guidance.
- [ ] Validate YAML, links, workflow syntax and documentation.
- [ ] Commit the automation change.

### Task 5: Version Freeze and Application Verification

**Files:**
- Modify: `study_assistant-1.1.0/local_app/pubspec.yaml`
- Modify: `study_assistant-1.1.0/local_app/lib/src/app/app_version.dart`
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/guides/安装与使用.md`
- Test: update suite and full Flutter suite.

**Interfaces:**
- Consumes: working client and automation code.
- Produces: signed `1.7.52+59` candidate and formal release artifacts.

- [ ] Add failing version-metadata assertions for `1.7.52+59`, bump version files and user-facing version declarations.
- [ ] Run metadata, format, analyze, update tests, full tests and dual-timezone checks.
- [ ] Build Debug and signed two-ABI Release; verify package, version, signature, ABI, ZIP and 16KiB alignment.
- [ ] Install the final APK into MuMu without clearing data; verify preserved session, Gitee-first success and GitHub fallback.
- [ ] Commit version and validation records.

### Task 6: GitHub Delivery, Gitee Seed and Final Verification

**Files:**
- Modify: docs and review records with final IDs, URLs, hashes and failures.

**Interfaces:**
- Consumes: verified code, `GITEE_TOKEN`, final GitHub Release.
- Produces: public GitHub release, Gitee seed, daily scheduler, and final acceptance evidence.

- [ ] Push branch, open PR, wait for all CI, merge to main and wait for main CI.
- [ ] Build again from final main, create annotated tag and public GitHub release, and wait for Tag CI.
- [ ] Bootstrap Gitee with the seed workflow.
- [ ] Verify public Gitee stable/manual JSON, anonymous APK downloads and 3-APK retention.
- [ ] Verify scheduled workflow exists.
- [ ] Record final IDs and URLs, run final document CI, and report remaining external-network limitations.
